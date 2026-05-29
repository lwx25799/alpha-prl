#!/usr/bin/env bash
set -euo pipefail

SESSION="${SESSION:-prl-alpha}"
OLD_SESSION="${OLD_SESSION:-prl}"
MINER_DIR="${MINER_DIR:-$HOME/alpha-miner}"
MINER_URL="${MINER_URL:-https://pearl.alphapool.tech/downloads/alpha-miner}"

WALLET="${WALLET:-prl1p98xudnvdsy4rtuw67zdq9xg52ewsghcycqagfy23nyg4c82qr3nsknlga7}"
WORKER="${WORKER:-$(hostname)-alpha}"
DIFFICULTY="${DIFFICULTY:-}"

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

if screen -list | grep -q "[.]${OLD_SESSION}[[:space:]]"; then
  echo "[*] Stopping old P-pool session: ${OLD_SESSION}"
  screen -S "${OLD_SESSION}" -X quit || true
  sleep 2
fi

test_endpoint() {
  local endpoint="$1"
  local host="${endpoint%:*}"
  local port="${endpoint##*:}"
  local t

  t="$(curl -sS --connect-timeout 3 --max-time 4 \
    -o /dev/null -w "%{time_connect}" "telnet://${host}:${port}" 2>/dev/null || true)"

  case "$t" in
    ""|0|0.000000) return 1 ;;
  esac

  awk "BEGIN { printf \"%d\", $t * 1000 }"
}

echo "[*] Testing AlphaPool endpoints..."

BEST_ENDPOINT=""
BEST_LATENCY=999999

for endpoint in "${ENDPOINTS[@]}"; do
  if latency="$(test_endpoint "$endpoint")"; then
    echo "    [OK]   $endpoint ${latency}ms"
    if [ "$latency" -lt "$BEST_LATENCY" ]; then
      BEST_LATENCY="$latency"
      BEST_ENDPOINT="$endpoint"
    fi
  else
    echo "    [FAIL] $endpoint timeout"
  fi
done

if [ -z "$BEST_ENDPOINT" ]; then
  echo "[!] No AlphaPool endpoint available."
  exit 1
fi

POOL_URL="stratum+tcp://${BEST_ENDPOINT}"

echo "[+] Best endpoint: ${BEST_ENDPOINT} ${BEST_LATENCY}ms"
echo "[+] Pool URL: ${POOL_URL}"

mkdir -p "$MINER_DIR"

PASSWORD_ARGS=""
if [ -n "$DIFFICULTY" ]; then
  PASSWORD_ARGS="--password 'x;d=${DIFFICULTY}'"
fi

screen -dmS "$SESSION" bash -lc "
  set -e
  cd '$MINER_DIR'

  echo '[*] Downloading latest alpha-miner...'
  curl -fL --retry 3 '$MINER_URL' -o alpha-miner
  chmod +x alpha-miner

  echo '[*] Starting PRL miner on AlphaPool...'
  echo '[*] Pool:   $POOL_URL'
  echo '[*] Wallet: $WALLET'
  echo '[*] Worker: $WORKER'

  ./alpha-miner \
    --pool '$POOL_URL' \
    --address '$WALLET' \
    --worker '$WORKER' \
    $PASSWORD_ARGS \
    2>&1 | tee alpha-miner.log

  echo ''
  echo '[!] Miner exited. Check the error above.'
  exec bash
"

echo "[+] Started AlphaPool PRL miner."
echo "    Screen: screen -r ${SESSION}"
echo "    Detach: Ctrl+A then D"
echo "    Stop:   screen -S ${SESSION} -X quit"
echo "    Log:    tail -f ${MINER_DIR}/alpha-miner.log"
echo "    Pool:   ${POOL_URL}"
echo "    Worker: ${WORKER}"
