#!/usr/bin/env bash
set -euo pipefail

SESSION="${SESSION:-prl}"
OLD_SESSION="${OLD_SESSION:-prl-alpha}"
MINER_DIR="${MINER_DIR:-$HOME/prl-miner}"
MINER_URL="${MINER_URL:-https://pearlhash.xyz/downloads/pearl-miner-v8}"
LOG_FILE="${MINER_DIR}/pearl-miner.log"

WALLET="${WALLET:-prl1p3vrzmwfn5m9u85z6amfgt8chhclc396wgrnrev4hz29ra3klqd0ql3nj7p}"
WORKER="${WORKER:-$(hostname)-p}"
POOL_ENDPOINT="${POOL_ENDPOINT:-auto}"
KEEP_ALIVE="${KEEP_ALIVE:-1}"

ENDPOINTS=(
  "84.32.220.219:9000"
  "129.226.55.135:9000"
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

if ! command -v screen >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  echo "[*] Installing dependencies..."
  install_deps
fi

if screen -list | grep -q "[.]${SESSION}[[:space:]]"; then
  echo "[!] Pearlhash miner already running."
  echo "    Attach: screen -r ${SESSION}"
  echo "    Stop:   screen -S ${SESSION} -X quit"
  exit 0
fi

test_endpoint() {
  local endpoint="$1"
  local host="${endpoint%:*}"
  local port="${endpoint##*:}"
  local t
  local curl_cmd

  curl_cmd=(curl -4 -sS --connect-timeout 2 --max-time 3 \
    -o /dev/null -w "%{time_connect}" "telnet://${host}:${port}")

  if command -v timeout >/dev/null 2>&1; then
    t="$(timeout 5s "${curl_cmd[@]}" 2>/dev/null || true)"
  else
    t="$("${curl_cmd[@]}" 2>/dev/null || true)"
  fi

  case "$t" in
    ""|0|0.000000) return 1 ;;
  esac

  awk "BEGIN { printf \"%d\", $t * 1000 }"
}

filter_pearl_log() {
  awk '
    {
      line = tolower($0)
      if (line ~ /(accept|accepted|component=share submitted|share submitted|submitted)/) {
        accepted += 1
        if (accepted == 1 || accepted % 20 == 0) {
          print "[*] Accepted shares: " accepted
          fflush()
        }
      } else if (line ~ /(hashrate|hash rate|[kmgtpe]?h\/s)/) {
        gsub(/^[0-9TZ:.-]+[ ]+/, "", $0)
        print "[*] " $0
        fflush()
      } else if (line ~ /(error|fail|warn|reject|rejected|stale|invalid|disconnect)/) {
        print
        fflush()
      }
    }
  '
}

case "$POOL_ENDPOINT" in
  eu-us|eu|us)
    POOL_ENDPOINT="84.32.220.219:9000"
    ;;
  asia|cn|china)
    POOL_ENDPOINT="129.226.55.135:9000"
    ;;
esac

if [ "$POOL_ENDPOINT" = "auto" ]; then
  echo "[*] Testing Pearlhash endpoints..."

  BEST_ENDPOINT=""
  BEST_LATENCY=999999

  for endpoint in "${ENDPOINTS[@]}"; do
    printf "    [..]   %s ... " "$endpoint"
    if latency="$(test_endpoint "$endpoint")"; then
      echo "OK ${latency}ms"
      if [ "$latency" -lt "$BEST_LATENCY" ]; then
        BEST_LATENCY="$latency"
        BEST_ENDPOINT="$endpoint"
      fi
    else
      echo "FAIL"
    fi
  done

  if [ -z "$BEST_ENDPOINT" ]; then
    echo "[!] No Pearlhash endpoint available."
    exit 1
  fi

  POOL_ENDPOINT="$BEST_ENDPOINT"
  echo "[+] Best endpoint: ${POOL_ENDPOINT} ${BEST_LATENCY}ms"
else
  echo "[*] Using Pearlhash endpoint: ${POOL_ENDPOINT}"
fi

echo "[+] Pool host: ${POOL_ENDPOINT}"

mkdir -p "$MINER_DIR"
touch "$LOG_FILE"

echo "[*] Downloading latest pearl-miner..."
curl -fL --retry 3 "$MINER_URL" -o "${MINER_DIR}/pearl-miner"
chmod +x "${MINER_DIR}/pearl-miner"

if [ -n "$OLD_SESSION" ] && screen -list | grep -q "[.]${OLD_SESSION}[[:space:]]"; then
  echo "[*] Stopping old AlphaPool session: ${OLD_SESSION}"
  screen -S "${OLD_SESSION}" -X quit || true
  sleep 2
fi

screen -dmS "$SESSION" bash -lc "
  set -e

  $(declare -f filter_pearl_log)

  cd '$MINER_DIR'

  echo '[*] Starting PRL miner on Pearlhash...'
  echo '[*] Host:   $POOL_ENDPOINT'
  echo '[*] Wallet: $WALLET'
  echo '[*] Worker: $WORKER'
  echo '[*] Screen output is filtered. Full log: pearl-miner.log'

  ./pearl-miner \
    --host '$POOL_ENDPOINT' \
    --user '$WALLET' \
    --worker '$WORKER' \
    2>&1 | tee pearl-miner.log | filter_pearl_log || true

  echo ''
  echo '[!] Miner exited. Check the error above.'
"

sleep 3
if ! screen -list | grep -q "[.]${SESSION}[[:space:]]"; then
  echo "[!] Pearlhash miner failed to stay running."
  echo "    Old session was already stopped before launch."
  echo "    Log: tail -f ${MINER_DIR}/pearl-miner.log"
  exit 1
fi

echo "[+] Started Pearlhash PRL miner."
echo "    Screen: screen -r ${SESSION}"
echo "    Detach: Ctrl+A then D"
echo "    Stop:   screen -S ${SESSION} -X quit"
echo "    Log:    tail -f ${MINER_DIR}/pearl-miner.log"
echo "    Host:   ${POOL_ENDPOINT}"
echo "    Worker: ${WORKER}"

if [ "$KEEP_ALIVE" = "1" ]; then
  echo ""
  echo "[*] Keeping startup command alive by following a filtered miner summary."
  echo "    Press Ctrl+C to leave this view; the miner keeps running in screen."
  tail -n 80 -F "$LOG_FILE" | filter_pearl_log
fi
