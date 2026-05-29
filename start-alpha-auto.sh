#!/usr/bin/env bash
set -euo pipefail

SESSION="${SESSION:-prl-alpha}"
OLD_SESSION="${OLD_SESSION:-prl}"
MINER_DIR="${MINER_DIR:-$HOME/alpha-miner}"
MINER_URL="${MINER_URL:-https://pearl.alphapool.tech/downloads/alpha-miner}"

WALLET="${WALLET:-prl1p3vrzmwfn5m9u85z6amfgt8chhclc396wgrnrev4hz29ra3klqd0ql3nj7p}"
WORKER="${WORKER:-$(hostname)-alpha}"
DIFFICULTY="${DIFFICULTY:-}"
POOL_ENDPOINT="${POOL_ENDPOINT:-auto}"
ENDPOINT_TIMEOUT="${ENDPOINT_TIMEOUT:-3}"
ENDPOINT_TESTS="${ENDPOINT_TESTS:-3}"

ENDPOINTS=(
  "us1.alphapool.tech:5566"
  "us2.alphapool.tech:5566"
  "eu1.alphapool.tech:5566"
  "eu2.alphapool.tech:5566"
  "ru1.alphapool.tech:5566"
  "sg1.alphapool.tech:5566"
)

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update
    $SUDO apt-get install -y screen curl
  elif command -v yum >/dev/null 2>&1; then
    $SUDO yum install -y screen curl
  elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf install -y screen curl
  elif command -v pacman >/dev/null 2>&1; then
    $SUDO pacman -Sy --noconfirm screen curl
  elif command -v apk >/dev/null 2>&1; then
    $SUDO apk add screen curl
  else
    echo "[!] No supported package manager found. Please install screen and curl manually."
    exit 1
  fi
}

now_ms() {
  local ts

  ts="$(date +%s%3N 2>/dev/null || true)"
  if [[ "$ts" =~ ^[0-9]+$ ]]; then
    echo "$ts"
    return
  fi

  echo "$(date +%s)000"
}

if ! command -v screen >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  echo "[*] Installing dependencies..."
  install_deps
fi

if screen -list | grep -q "[.]${SESSION}[[:space:]]"; then
  echo "[!] AlphaPool miner already running."
  echo "    Attach: screen -r ${SESSION}"
  echo "    Stop:   screen -S ${SESSION} -X quit"
  exit 0
fi

test_endpoint() {
  local endpoint="$1"
  local host="${endpoint%:*}"
  local port="${endpoint##*:}"
  local start
  local end

  start="$(now_ms)"

  if command -v timeout >/dev/null 2>&1; then
    timeout "${ENDPOINT_TIMEOUT}s" bash -c "</dev/tcp/$host/$port" 2>/dev/null || return 1
  else
    bash -c "</dev/tcp/$host/$port" 2>/dev/null || return 1
  fi

  end="$(now_ms)"
  echo $((end - start))
}

test_endpoint_precise() {
  local endpoint="$1"
  local samples=()
  local latency
  local sorted
  local median
  local i

  for ((i = 1; i <= ENDPOINT_TESTS; i++)); do
    if latency="$(test_endpoint "$endpoint")"; then
      samples+=("$latency")
    fi
  done

  if [ "${#samples[@]}" -eq 0 ]; then
    return 1
  fi

  sorted="$(printf "%s\n" "${samples[@]}" | sort -n)"
  median="$(printf "%s\n" "$sorted" | sed -n "$(((${#samples[@]} + 1) / 2))p")"
  printf "%s %s" "$median" "$(printf "%s" "$sorted" | tr '\n' ' ')"
}

if [ "$POOL_ENDPOINT" = "auto" ]; then
  echo "[*] Testing AlphaPool endpoints..."

  BEST_ENDPOINT=""
  BEST_LATENCY=999999

  for endpoint in "${ENDPOINTS[@]}"; do
    printf "    [..]   %s ... " "$endpoint"
    if result="$(test_endpoint_precise "$endpoint")"; then
      latency="${result%% *}"
      samples="${result#* }"
      echo "OK ${latency}ms (samples: ${samples})"
      if [ "$latency" -lt "$BEST_LATENCY" ]; then
        BEST_LATENCY="$latency"
        BEST_ENDPOINT="$endpoint"
      fi
    else
      echo "FAIL"
    fi
  done

  if [ -z "$BEST_ENDPOINT" ]; then
    echo "[!] No AlphaPool endpoint available."
    exit 1
  fi

  POOL_ENDPOINT="$BEST_ENDPOINT"
  echo "[+] Best endpoint: ${POOL_ENDPOINT} ${BEST_LATENCY}ms"
else
  echo "[*] Using AlphaPool endpoint: ${POOL_ENDPOINT}"
fi

POOL_URL="stratum+tcp://${POOL_ENDPOINT}"

echo "[+] Pool URL: ${POOL_URL}"

mkdir -p "$MINER_DIR"

PASSWORD_ARGS=""
if [ -n "$DIFFICULTY" ]; then
  PASSWORD_ARGS="--password 'x;d=${DIFFICULTY}'"
fi

echo "[*] Downloading latest alpha-miner..."
curl -fL --retry 3 "$MINER_URL" -o "${MINER_DIR}/alpha-miner"
chmod +x "${MINER_DIR}/alpha-miner"

if screen -list | grep -q "[.]${OLD_SESSION}[[:space:]]"; then
  echo "[*] Stopping old P-pool session: ${OLD_SESSION}"
  screen -S "${OLD_SESSION}" -X quit || true
  sleep 2
fi

screen -dmS "$SESSION" bash -lc "
  set -e
  cd '$MINER_DIR'

  echo '[*] Starting PRL miner on AlphaPool...'
  echo '[*] Pool:   $POOL_URL'
  echo '[*] Wallet: $WALLET'
  echo '[*] Worker: $WORKER'
  echo '[*] Screen output is filtered. Full log: alpha-miner.log'

  ./alpha-miner \
    --pool '$POOL_URL' \
    --address '$WALLET' \
    --worker '$WORKER' \
    $PASSWORD_ARGS \
    2>&1 | tee alpha-miner.log | awk '
      {
        line = tolower(\$0)
        if (line ~ /(accept|accepted)/) {
          accepted += 1
          if (accepted == 1 || accepted % 20 == 0) {
            print \"[*] Accepted shares: \" accepted
            fflush()
          }
        } else if (line ~ /(hashrate|hash rate|[kmgtpe]?h\/s|effective|equiv|equivalent|pool.*(hash|eff|equiv)|error|fail|warn|reject|rejected|stale|invalid|disconnect|connected|difficulty)/) {
          print
          fflush()
        }
      }
    ' || true

  echo ''
  echo '[!] Miner exited. Check the error above.'
"

sleep 3
if ! screen -list | grep -q "[.]${SESSION}[[:space:]]"; then
  echo "[!] AlphaPool miner failed to stay running."
  echo "    Old session was already stopped before launch."
  echo "    Log: tail -f ${MINER_DIR}/alpha-miner.log"
  exit 1
fi

echo "[+] Started AlphaPool PRL miner."
echo "    Screen: screen -r ${SESSION}"
echo "    Detach: Ctrl+A then D"
echo "    Stop:   screen -S ${SESSION} -X quit"
echo "    Log:    tail -f ${MINER_DIR}/alpha-miner.log"
echo "    Pool:   ${POOL_URL}"
echo "    Worker: ${WORKER}"
