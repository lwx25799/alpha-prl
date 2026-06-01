#!/usr/bin/env bash
set -euo pipefail

SESSION="${SESSION:-prl-alpha}"
OLD_SESSION="${OLD_SESSION:-prl}"
MINER_DIR="${MINER_DIR:-$HOME/alpha-miner}"
OLD_MINER_DIR="${OLD_MINER_DIR:-$HOME/prl-miner}"
MINER_URL="${MINER_URL:-https://pearl.alphapool.tech/downloads/alpha-miner}"
MINER_BIN="${MINER_DIR}/alpha-miner"
OLD_MINER_BIN="${OLD_MINER_DIR}/pearl-miner"
LOG_FILE="${MINER_DIR}/alpha-miner.log"
PID_FILE="${MINER_DIR}/${SESSION}.pid"
RUN_SCRIPT="${MINER_DIR}/run-alpha-miner.sh"
OLD_PID_FILE="${OLD_MINER_DIR}/${OLD_SESSION}.pid"

WALLET="${WALLET:-prl1p3vrzmwfn5m9u85z6amfgt8chhclc396wgrnrev4hz29ra3klqd0ql3nj7p}"
WORKER="${WORKER:-}"
DIFFICULTY="${DIFFICULTY:-}"
STATUS_INTERVAL="${STATUS_INTERVAL:-5}"
DEVICES="${DEVICES:-}"
POOL_ENDPOINT="${POOL_ENDPOINT:-auto}"
ENDPOINT_TIMEOUT="${ENDPOINT_TIMEOUT:-3}"
ENDPOINT_TESTS="${ENDPOINT_TESTS:-3}"
KEEP_ALIVE="${KEEP_ALIVE:-0}"
VIEW="${VIEW:-}"
STARTUP_WAIT="${STARTUP_WAIT:-30}"
LAUNCH_MODE="${LAUNCH_MODE:-auto}"
SKIP_DOWNLOAD="${SKIP_DOWNLOAD:-0}"
DEFAULT_MINER_DIR="${HOME}/alpha-miner"
STARTUP_LOG_LINES=0
STARTUP_HEALTH_REASON=""

ENDPOINTS=(
  "us1.alphapool.tech:5566"
  "us2.alphapool.tech:5566"
  "eu1.alphapool.tech:5566"
  "eu2.alphapool.tech:5566"
  "ru1.alphapool.tech:5566"
  "sg1.alphapool.tech:5566"
)

require_bash() {
  if [ -z "${BASH_VERSION:-}" ]; then
    echo "[!] This script requires bash. Run: bash $0"
    exit 1
  fi
}

default_worker_name() {
  local suffix="$1"
  local host="worker"

  if command -v hostname >/dev/null 2>&1; then
    host="$(hostname 2>/dev/null || true)"
  fi
  if [ -z "$host" ] && [ -n "${HOSTNAME:-}" ]; then
    host="$HOSTNAME"
  fi
  if [ -z "$host" ] && [ -n "${USER:-}" ]; then
    host="$USER"
  fi
  host="${host:-worker}"
  printf "%s-%s" "$host" "$suffix"
}

refresh_miner_paths() {
  MINER_BIN="${MINER_DIR}/alpha-miner"
  LOG_FILE="${MINER_DIR}/alpha-miner.log"
  PID_FILE="${MINER_DIR}/${SESSION}.pid"
  RUN_SCRIPT="${MINER_DIR}/run-alpha-miner.sh"
}

ensure_miner_dir_writable() {
  refresh_miner_paths

  if mkdir -p "$MINER_DIR" 2>/dev/null && touch "${MINER_DIR}/.writetest" 2>/dev/null; then
    rm -f "${MINER_DIR}/.writetest"
    return 0
  fi

  if [ "$MINER_DIR" = "$DEFAULT_MINER_DIR" ] || [ "$MINER_DIR" = "${HOME}/alpha-miner" ]; then
    local uid fallback
    uid="$(id -u 2>/dev/null || echo 0)"
    for fallback in \
      "${TMPDIR:-}/alpha-miner-${uid}" \
      "/tmp/alpha-miner-${uid}" \
      "${TMPDIR:-}/alpha-miner" \
      "/tmp/alpha-miner"; do
      [ -z "$fallback" ] && continue
      if mkdir -p "$fallback" 2>/dev/null && touch "${fallback}/.writetest" 2>/dev/null; then
        rm -f "${fallback}/.writetest"
        echo "[*] ${MINER_DIR} is not writable; using ${fallback}"
        MINER_DIR="$fallback"
        refresh_miner_paths
        return 0
      fi
    done
  fi

  echo "[!] MINER_DIR is not writable: ${MINER_DIR}"
  echo "    Set MINER_DIR to a writable path and retry."
  exit 1
}

install_deps() {
  local sudo_cmd=()
  local pkgs=()

  if [ "$(id -u)" -eq 0 ]; then
    sudo_cmd=()
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo_cmd=(sudo -n)
  else
    echo "[*] sudo is unavailable; skipping system dependency install."
    return 0
  fi

  if ! command -v screen >/dev/null 2>&1; then
    pkgs+=(screen)
  fi
  if ! has_downloader; then
    pkgs+=(curl)
  fi

  if [ "${#pkgs[@]}" -eq 0 ]; then
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    "${sudo_cmd[@]}" apt-get update
    "${sudo_cmd[@]}" apt-get install -y "${pkgs[@]}"
  elif command -v yum >/dev/null 2>&1; then
    "${sudo_cmd[@]}" yum install -y "${pkgs[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    "${sudo_cmd[@]}" dnf install -y "${pkgs[@]}"
  elif command -v pacman >/dev/null 2>&1; then
    "${sudo_cmd[@]}" pacman -Sy --noconfirm "${pkgs[@]}"
  elif command -v apk >/dev/null 2>&1; then
    "${sudo_cmd[@]}" apk add "${pkgs[@]}"
  else
    echo "[!] No supported package manager found. Please install ${pkgs[*]} manually."
    return 1
  fi

  if ! has_downloader; then
    echo "[!] Package install finished, but no downloader is available yet."
    return 1
  fi
}

downloader_name() {
  if command -v curl >/dev/null 2>&1; then
    echo "curl"
  elif command -v wget >/dev/null 2>&1; then
    echo "wget"
  elif command -v busybox >/dev/null 2>&1 && busybox wget --help >/dev/null 2>&1; then
    echo "busybox wget"
  elif command -v python3 >/dev/null 2>&1; then
    echo "python3"
  elif command -v python >/dev/null 2>&1; then
    echo "python"
  elif command -v node >/dev/null 2>&1; then
    echo "node"
  else
    echo "none"
  fi
}

log_downloader() {
  local name

  name="$(downloader_name)"
  if [ "$name" = "none" ]; then
    return 1
  fi

  if command -v curl >/dev/null 2>&1; then
    echo "[*] Download tool: ${name}"
  else
    echo "[*] curl not found; using ${name} for downloads."
  fi
  return 0
}

require_downloader_unless_skip() {
  if [ "$SKIP_DOWNLOAD" = "1" ]; then
    return 0
  fi

  if has_downloader; then
    log_downloader
    return 0
  fi

  print_downloader_help
  exit 1
}

print_downloader_help() {
  echo "[!] No downloader found. This script needs one of: curl, wget, busybox wget, python3, python, or node."
  echo "    Or upload the miner binary and run with SKIP_DOWNLOAD=1."
  echo ""
  echo "    Examples without curl:"
  echo "    wget -O ${MINER_BIN} ${MINER_URL}"
  echo "    python3 - <<'PY'"
  echo "from urllib.request import urlretrieve"
  echo "urlretrieve('${MINER_URL}', '${MINER_BIN}')"
  echo "PY"
}

has_downloader() {
  command -v curl >/dev/null 2>&1 \
    || command -v wget >/dev/null 2>&1 \
    || { command -v busybox >/dev/null 2>&1 && busybox wget --help >/dev/null 2>&1; } \
    || command -v python3 >/dev/null 2>&1 \
    || command -v python >/dev/null 2>&1 \
    || command -v node >/dev/null 2>&1
}

ensure_optional_deps() {
  if command -v screen >/dev/null 2>&1 && has_downloader; then
    log_downloader || true
    return
  fi

  if [ "$(id -u)" -eq 0 ] || { command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; }; then
    echo "[*] Installing missing optional dependencies..."
    install_deps || echo "[*] Dependency install failed; continuing with user-space fallbacks."
  elif has_downloader; then
    log_downloader || true
  else
    echo "[*] sudo is unavailable and no downloader was found."
  fi
}

python_download() {
  local python_bin="$1"
  local url="$2"
  local output="$3"

  "$python_bin" - "$url" "$output" <<'PY'
import ssl
import sys

try:
    from urllib.request import Request, urlopen
except ImportError:
    from urllib2 import Request, urlopen

url, output = sys.argv[1], sys.argv[2]
request = Request(url, headers={"User-Agent": "alpha-prl-miner/1.0"})

def download(context=None):
    response = urlopen(request, timeout=60, context=context)
    with open(output, "wb") as fh:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            fh.write(chunk)

try:
    download()
except Exception as exc:
    text = str(exc).lower()
    if "certificate" in text or "ssl" in text:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        download(ctx)
    else:
        raise
PY
}

node_download() {
  local url="$1"
  local output="$2"

  node - "$url" "$output" <<'JS'
const fs = require("fs");
const https = require("https");
const http = require("http");

function download(currentUrl, output, redirectsLeft, callback) {
  const client = currentUrl.startsWith("https:") ? https : http;
  const req = client.get(
    currentUrl,
    { timeout: 60000, headers: { "User-Agent": "alpha-prl-miner/1.0" } },
    (response) => {
      if (
        response.statusCode >= 300 &&
        response.statusCode < 400 &&
        response.headers.location &&
        redirectsLeft > 0
      ) {
        download(response.headers.location, output, redirectsLeft - 1, callback);
        return;
      }
      if (response.statusCode !== 200) {
        callback(new Error(`HTTP ${response.statusCode}`));
        return;
      }
      const file = fs.createWriteStream(output);
      response.pipe(file);
      file.on("finish", () => file.close(callback));
      file.on("error", callback);
    }
  );
  req.on("error", callback);
}

const url = process.argv[2];
const output = process.argv[3];
download(url, output, 5, (err) => {
  if (err) {
    console.error(err.message);
    process.exit(1);
  }
});
JS
}

wget_download() {
  local url="$1"
  local output="$2"
  shift 2

  if "$@" --help 2>&1 | grep -q no-check-certificate; then
    "$@" -q --tries=3 --timeout=30 -O "$output" "$url" \
      || "$@" --tries=3 --timeout=30 -O "$output" "$url" \
      || "$@" --no-check-certificate --tries=3 --timeout=30 -O "$output" "$url"
  else
    "$@" -q -O "$output" "$url" || "$@" -O "$output" "$url"
  fi
}

download_file() {
  local url="$1"
  local output="$2"
  local tmp="${output}.part.$$"

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 15 --max-time 300 "$url" -o "$tmp" \
      || curl -kLf --retry 3 --connect-timeout 15 --max-time 300 "$url" -o "$tmp"
  elif command -v wget >/dev/null 2>&1; then
    wget_download "$url" "$tmp" wget
  elif command -v busybox >/dev/null 2>&1 && busybox wget --help >/dev/null 2>&1; then
    wget_download "$url" "$tmp" busybox wget
  elif command -v python3 >/dev/null 2>&1; then
    python_download python3 "$url" "$tmp"
  elif command -v python >/dev/null 2>&1; then
    python_download python "$url" "$tmp"
  elif command -v node >/dev/null 2>&1; then
    node_download "$url" "$tmp"
  else
    print_downloader_help
    exit 1
  fi

  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    echo "[!] Download failed or returned an empty file: ${url}"
    print_downloader_help
    exit 1
  fi

  mv -f "$tmp" "$output"
}

verify_miner_binary() {
  if [ ! -f "$MINER_BIN" ] || [ ! -s "$MINER_BIN" ]; then
    echo "[!] Miner binary missing or empty: ${MINER_BIN}"
    exit 1
  fi

  chmod +x "$MINER_BIN" 2>/dev/null || true
  if [ ! -x "$MINER_BIN" ]; then
    echo "[!] Miner binary is not executable: ${MINER_BIN}"
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

filter_alpha_log() {
  awk '
    function add_gpu(g) {
      if (!(g in seen)) {
        seen[g] = 1
        order[++gpu_count] = g
      }
    }

    function print_hashrate(    i, g, total, equiv_total, parts) {
      total = 0
      equiv_total = 0
      parts = ""

      for (i = 1; i <= gpu_count; i++) {
        g = order[i]
        total += gpu_hash[g]
        equiv_total += gpu_equiv[g]
        parts = parts sprintf(" gpu%s=%.2f TH/s", g, gpu_hash[g])
      }

      if (equiv_total > 0) {
        printf "[*] Hashrate: total=%.2f TH/s pool_equiv=%.2f TH/s |%s\n", total, equiv_total, parts
      } else {
        printf "[*] Hashrate: total=%.2f TH/s |%s\n", total, parts
      }
      fflush()
    }

    {
      line = tolower($0)
      if (line ~ /component=miner status/) {
        gpu = hash = equiv = ""
        if (match($0, /gpu=[0-9]+/)) gpu = substr($0, RSTART + 4, RLENGTH - 4)
        if (match($0, /hashrate_th_s=[0-9.]+/)) hash = substr($0, RSTART + 14, RLENGTH - 14)
        if (match($0, /share_equiv_th_s=[0-9.]+/)) equiv = substr($0, RSTART + 17, RLENGTH - 17)

        if (hash != "") {
          if (gpu == "") gpu = "?"
          add_gpu(gpu)
          gpu_hash[gpu] = hash + 0
          gpu_equiv[gpu] = equiv + 0
          print_hashrate()
        }
      } else if (line ~ /(error|fail|warn|reject|rejected|stale|invalid|disconnect)/) {
        print
        fflush()
      }
    }
  '
}

screen_session_running() {
  local session="$1"

  command -v screen >/dev/null 2>&1 || return 1
  screen -list 2>/dev/null | awk -v session="$session" '
    $1 ~ /^[0-9]+[.]/ {
      name = $1
      sub(/^[0-9]+[.]/, "", name)
      if (name == session) found = 1
    }
    END { exit found ? 0 : 1 }
  '
}

is_screen_session_running() {
  screen_session_running "$SESSION"
}

read_pid_file() {
  local pid_file="$1"
  local pid

  [ -f "$pid_file" ] || return 1
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  case "$pid" in
    ""|*[!0-9]*) return 1 ;;
  esac

  printf "%s" "$pid"
}

canonical_path() {
  local path="$1"
  local dir
  local base

  dir="$(dirname "$path")"
  base="$(basename "$path")"

  if dir="$(cd "$dir" 2>/dev/null && pwd -P)"; then
    printf "%s/%s" "$dir" "$base"
  else
    printf "%s" "$path"
  fi
}

pid_matches_command() {
  local pid="$1"
  local expected="$2"
  local expected_real
  local exe
  local arg

  expected_real="$(canonical_path "$expected")"

  if [ -e "/proc/${pid}/exe" ]; then
    exe="$(readlink "/proc/${pid}/exe" 2>/dev/null || true)"
    case "$exe" in
      "$expected_real"|"$expected_real (deleted)") return 0 ;;
    esac
  fi

  if [ -r "/proc/${pid}/cmdline" ]; then
    while IFS= read -r -d '' arg; do
      if [ "$arg" = "$expected" ] || [ "$arg" = "$expected_real" ]; then
        return 0
      fi
    done < "/proc/${pid}/cmdline"

    if tr '\0' ' ' < "/proc/${pid}/cmdline" | grep -q "$(basename "$expected")"; then
      return 0
    fi
  fi

  return 1
}

is_pid_running() {
  local pid

  pid="$(read_pid_file "$PID_FILE")" || {
    rm -f "$PID_FILE"
    return 1
  }

  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$PID_FILE"
    return 1
  fi

  if pid_matches_command "$pid" "$MINER_BIN"; then
    return 0
  fi

  echo "[!] Ignoring stale PID file: ${PID_FILE} points to non-AlphaPool process ${pid}."
  rm -f "$PID_FILE"
  return 1
}

is_current_running() {
  is_screen_session_running || is_pid_running
}

record_startup_log_position() {
  local lines

  if [ -f "$LOG_FILE" ]; then
    lines="$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d '[:space:]')" || lines=0
    case "$lines" in
      ""|*[!0-9]*)
        lines=0
        ;;
    esac
    STARTUP_LOG_LINES="$lines"
  else
    STARTUP_LOG_LINES=0
  fi
}

startup_hashrate_seen() {
  [ -f "$LOG_FILE" ] || return 1

  awk -v start="$STARTUP_LOG_LINES" '
    NR > start {
      line = tolower($0)
      if ((line ~ /component=miner status/ && line ~ /hashrate_th_s=/) || line ~ /hashrate: total=/) {
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  ' "$LOG_FILE"
}

wait_for_pid_exit() {
  local pid="$1"
  local i

  for ((i = 0; i < 10; i++)); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 1
  done

  return 1
}

wait_for_screen_session_exit() {
  local session="$1"
  local i

  for ((i = 0; i < 10; i++)); do
    screen_session_running "$session" || return 0
    sleep 1
  done

  return 1
}

stop_pid_file() {
  local pid_file="$1"
  local expected_bin="$2"
  local label="$3"
  local pid

  pid="$(read_pid_file "$pid_file")" || {
    rm -f "$pid_file"
    return 1
  }

  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$pid_file"
    return 1
  fi

  if ! pid_matches_command "$pid" "$expected_bin"; then
    echo "[!] Ignoring stale ${label} PID file: ${pid_file} points to unrelated process ${pid}."
    rm -f "$pid_file"
    return 1
  fi

  echo "[*] Stopping ${label} background process: ${pid}"
  kill "$pid" || true

  if wait_for_pid_exit "$pid"; then
    rm -f "$pid_file"
    return 0
  fi

  echo "[!] ${label} background process did not stop after SIGTERM: ${pid}"
  return 2
}

stop_old_session() {
  local stop_status

  if [ -n "$OLD_SESSION" ] && screen_session_running "$OLD_SESSION"; then
    echo "[*] Stopping old P-pool screen session: ${OLD_SESSION}"
    screen -S "${OLD_SESSION}" -X quit || true
    if wait_for_screen_session_exit "$OLD_SESSION"; then
      :
    else
      echo "[!] Old P-pool screen session did not stop: ${OLD_SESSION}"
      exit 1
    fi
  fi

  if [ -n "$OLD_SESSION" ] && [ -f "$OLD_PID_FILE" ]; then
    if stop_pid_file "$OLD_PID_FILE" "$OLD_MINER_BIN" "old P-pool"; then
      :
    else
      stop_status="$?"
      if [ "$stop_status" = "2" ]; then
        exit 1
      fi
    fi
  fi
}

require_bash

if [ "$VIEW" = "summary" ]; then
  ensure_miner_dir_writable
  if [ ! -f "$LOG_FILE" ]; then
    echo "[!] AlphaPool log not found: ${LOG_FILE}"
    exit 1
  fi

  tail -n "${SUMMARY_LINES:-200}" "$LOG_FILE" | filter_alpha_log
  exit 0
fi

ensure_optional_deps
WORKER="${WORKER:-$(default_worker_name alpha)}"
require_downloader_unless_skip

if is_current_running; then
  echo "[!] AlphaPool miner already running."
  if is_screen_session_running; then
    echo "    Attach: screen -r ${SESSION}"
    echo "    Stop:   screen -S ${SESSION} -X quit"
  else
    echo "    PID:    $(cat "$PID_FILE" 2>/dev/null || true)"
    echo "    Stop:   kill \"\$(cat ${PID_FILE})\""
    echo "    Log:    tail -n 80 ${LOG_FILE}"
  fi
  exit 0
fi

python_tcp_probe() {
  local host="$1"
  local port="$2"
  local python_bin="$3"

  "$python_bin" - "$host" "$port" "$ENDPOINT_TIMEOUT" <<'PY'
import socket
import sys

host, port, timeout = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(timeout)
sock.connect((host, port))
sock.close()
PY
}

nc_tcp_probe() {
  local host="$1"
  local port="$2"

  if command -v nc >/dev/null 2>&1; then
    nc -z -w "$ENDPOINT_TIMEOUT" "$host" "$port" 2>/dev/null
  elif command -v ncat >/dev/null 2>&1; then
    ncat -z -w "$ENDPOINT_TIMEOUT" "$host" "$port" 2>/dev/null
  elif command -v busybox >/dev/null 2>&1; then
    busybox nc -z -w "$ENDPOINT_TIMEOUT" "$host" "$port" 2>/dev/null
  else
    return 1
  fi
}

bash_tcp_probe() {
  local host="$1"
  local port="$2"

  if command -v timeout >/dev/null 2>&1; then
    timeout "${ENDPOINT_TIMEOUT}s" bash -c "</dev/tcp/$host/$port" 2>/dev/null
  else
    bash -c "</dev/tcp/$host/$port" 2>/dev/null
  fi
}

curl_tcp_probe() {
  local host="$1"
  local port="$2"
  local t
  local curl_cmd

  curl_cmd=(curl -4 -sS --connect-timeout "$ENDPOINT_TIMEOUT" --max-time "$((ENDPOINT_TIMEOUT + 2))" \
    -o /dev/null -w "%{time_connect}" "telnet://${host}:${port}")

  if command -v timeout >/dev/null 2>&1; then
    t="$(timeout "$((ENDPOINT_TIMEOUT + 3))s" "${curl_cmd[@]}" 2>/dev/null || true)"
  else
    t="$("${curl_cmd[@]}" 2>/dev/null || true)"
  fi

  case "$t" in
    ""|0|0.000000) return 1 ;;
  esac

  awk "BEGIN { printf \"%d\", $t * 1000 }"
}

probe_tcp_endpoint() {
  local endpoint="$1"
  local host="${endpoint%:*}"
  local port="${endpoint##*:}"
  local start
  local end
  local curl_ms

  start="$(now_ms)"

  if curl_ms="$(curl_tcp_probe "$host" "$port")"; then
    echo "$curl_ms"
    return 0
  fi

  if bash_tcp_probe "$host" "$port"; then
    :
  elif nc_tcp_probe "$host" "$port"; then
    :
  elif command -v python3 >/dev/null 2>&1 && python_tcp_probe "$host" "$port" python3; then
    :
  elif command -v python >/dev/null 2>&1 && python_tcp_probe "$host" "$port" python; then
    :
  else
    return 1
  fi

  end="$(now_ms)"
  echo $((end - start))
}

test_endpoint() {
  probe_tcp_endpoint "$1"
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
    echo "    Set POOL_ENDPOINT manually, for example:"
    echo "    export POOL_ENDPOINT=\"sg1.alphapool.tech:5566\""
    exit 1
  fi

  POOL_ENDPOINT="$BEST_ENDPOINT"
  echo "[+] Best endpoint: ${POOL_ENDPOINT} ${BEST_LATENCY}ms"
else
  echo "[*] Using AlphaPool endpoint: ${POOL_ENDPOINT}"
fi

POOL_URL="stratum+tcp://${POOL_ENDPOINT}"

echo "[+] Pool URL: ${POOL_URL}"

ensure_miner_dir_writable
touch "$LOG_FILE"

if [ "$SKIP_DOWNLOAD" = "1" ]; then
  echo "[*] SKIP_DOWNLOAD=1; using existing miner binary."
  verify_miner_binary
else
  echo "[*] Downloading latest alpha-miner..."
  download_file "$MINER_URL" "$MINER_BIN"
  verify_miner_binary
fi

if command -v tee >/dev/null 2>&1; then
  ALPHA_LOG_RUN='"${args[@]}" 2>&1 | tee -a alpha-miner.log | filter_alpha_log || true'
else
  ALPHA_LOG_RUN='"${args[@]}" >> alpha-miner.log 2>&1'
fi

cat > "$RUN_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail

cleanup_children() {
  trap - TERM INT EXIT
  local child parent
  for parent in "\$\$" \$(jobs -pr); do
    while read -r child; do
      [ -n "\$child" ] || continue
      kill_tree "\$child"
    done <<CHILDREN
\$(ps -ef 2>/dev/null | awk -v p="\$parent" '\$3 == p { print \$2 }')
CHILDREN
  done
  for child in \$(jobs -pr); do
    kill "\$child" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}

kill_tree() {
  local pid="\$1"
  local child
  while read -r child; do
    [ -n "\$child" ] || continue
    kill_tree "\$child"
  done <<CHILDREN
\$(ps -ef 2>/dev/null | awk -v p="\$pid" '\$3 == p { print \$2 }')
CHILDREN
  kill "\$pid" 2>/dev/null || true
}
trap cleanup_children TERM INT EXIT

$(declare -f filter_alpha_log)

cd "\${MINER_DIR}"

echo '[*] Starting PRL miner on AlphaPool...'
echo "[*] Pool:   \${POOL_URL}"
echo "[*] Wallet: \${WALLET}"
echo "[*] Worker: \${WORKER}"
echo "[*] Status interval: \${STATUS_INTERVAL}s"
echo '[*] Full raw log: alpha-miner.log'

args=(
  ./alpha-miner
  --pool "\${POOL_URL}"
  --address "\${WALLET}"
  --worker "\${WORKER}"
  --status-interval "\${STATUS_INTERVAL}"
)

if [ -n "\${DEVICES:-}" ]; then
  args+=(--devices "\${DEVICES}")
fi

if [ -n "\${DIFFICULTY:-}" ]; then
  args+=(--password "x;d=\${DIFFICULTY}")
fi

run_miner() {
  ${ALPHA_LOG_RUN}
}

run_miner &
miner_job="\$!"
wait "\$miner_job"

echo ''
echo '[!] Miner exited. Check the error above.'
EOF
chmod +x "$RUN_SCRIPT"

launch_miner() {
  local mode="$1"

  case "$mode" in
    screen)
      screen -dmS "$SESSION" env \
        MINER_DIR="$MINER_DIR" \
        POOL_URL="$POOL_URL" \
        WALLET="$WALLET" \
        WORKER="$WORKER" \
        STATUS_INTERVAL="$STATUS_INTERVAL" \
        DEVICES="$DEVICES" \
        DIFFICULTY="$DIFFICULTY" \
        bash "$RUN_SCRIPT"
      ;;
    setsid)
      (
        cd "$MINER_DIR"
        setsid env \
          MINER_DIR="$MINER_DIR" \
          POOL_URL="$POOL_URL" \
          WALLET="$WALLET" \
          WORKER="$WORKER" \
          STATUS_INTERVAL="$STATUS_INTERVAL" \
          DEVICES="$DEVICES" \
          DIFFICULTY="$DIFFICULTY" \
          bash "$RUN_SCRIPT" >> "$LOG_FILE" 2>&1 &
        echo "$!" > "$PID_FILE"
      )
      ;;
    nohup)
      (
        cd "$MINER_DIR"
        nohup env \
          MINER_DIR="$MINER_DIR" \
          POOL_URL="$POOL_URL" \
          WALLET="$WALLET" \
          WORKER="$WORKER" \
          STATUS_INTERVAL="$STATUS_INTERVAL" \
          DEVICES="$DEVICES" \
          DIFFICULTY="$DIFFICULTY" \
          bash "$RUN_SCRIPT" >> "$LOG_FILE" 2>&1 &
        echo "$!" > "$PID_FILE"
      )
      ;;
    background)
      (
        cd "$MINER_DIR"
        env \
          MINER_DIR="$MINER_DIR" \
          POOL_URL="$POOL_URL" \
          WALLET="$WALLET" \
          WORKER="$WORKER" \
          STATUS_INTERVAL="$STATUS_INTERVAL" \
          DEVICES="$DEVICES" \
          DIFFICULTY="$DIFFICULTY" \
          bash "$RUN_SCRIPT" >> "$LOG_FILE" 2>&1 &
        echo "$!" > "$PID_FILE"
        disown 2>/dev/null || true
      )
      ;;
    *)
      echo "[!] Unknown LAUNCH_MODE: ${mode}"
      exit 1
      ;;
  esac
}

pick_launch_mode() {
  case "$LAUNCH_MODE" in
    screen)
      command -v screen >/dev/null 2>&1 || {
        echo "[!] LAUNCH_MODE=screen but screen is not installed."
        echo "    Try: export LAUNCH_MODE=auto"
        exit 1
      }
      printf "%s" "screen"
      ;;
    setsid)
      command -v setsid >/dev/null 2>&1 || {
        echo "[!] LAUNCH_MODE=setsid but setsid is not installed."
        echo "    Try: export LAUNCH_MODE=auto"
        exit 1
      }
      printf "%s" "setsid"
      ;;
    nohup)
      command -v nohup >/dev/null 2>&1 || {
        echo "[!] LAUNCH_MODE=nohup but nohup is not installed."
        echo "    Try: export LAUNCH_MODE=background"
        exit 1
      }
      printf "%s" "nohup"
      ;;
    background)
      printf "%s" "background"
      ;;
    auto)
      if command -v screen >/dev/null 2>&1; then
        printf "%s" "screen"
      elif command -v setsid >/dev/null 2>&1; then
        printf "%s" "setsid"
      elif command -v nohup >/dev/null 2>&1; then
        printf "%s" "nohup"
      else
        printf "%s" "background"
      fi
      ;;
    *)
      echo "[!] Invalid LAUNCH_MODE: ${LAUNCH_MODE} (use auto, screen, setsid, nohup, or background)"
      exit 1
      ;;
  esac
}

miner_is_ready() {
  case "$LAUNCH_MODE" in
    screen)
      is_screen_session_running
      ;;
    *)
      is_pid_running
      ;;
  esac
}

wait_for_miner_ready() {
  local i
  local saw_running=0

  STARTUP_HEALTH_REASON=""

  for ((i = 0; i < STARTUP_WAIT; i++)); do
    if miner_is_ready; then
      saw_running=1
    elif [ "$saw_running" = "1" ]; then
      STARTUP_HEALTH_REASON="miner exited during startup health check"
      return 1
    fi
    sleep 1
  done

  if ! miner_is_ready; then
    if [ "$saw_running" = "1" ]; then
      STARTUP_HEALTH_REASON="miner exited before startup health check completed"
    else
      STARTUP_HEALTH_REASON="miner never became visible to the launcher"
    fi
    return 1
  fi

  if startup_hashrate_seen; then
    STARTUP_HEALTH_REASON="hashrate log observed"
  else
    STARTUP_HEALTH_REASON="still running after ${STARTUP_WAIT}s"
  fi

  return 0
}

stop_old_session

LAUNCH_MODE="$(pick_launch_mode)"
case "$LAUNCH_MODE" in
  screen)
    echo "[*] Launch mode: screen (no sudo required if screen is already installed)."
    ;;
  setsid)
    echo "[*] Launch mode: setsid background (screen unavailable, no sudo required)."
    ;;
  nohup)
    echo "[*] Launch mode: nohup background (screen unavailable, no sudo required)."
    ;;
  background)
    echo "[*] Launch mode: plain background (minimal environment fallback)."
    ;;
esac

record_startup_log_position
launch_miner "$LAUNCH_MODE"
echo "[*] Waiting ${STARTUP_WAIT}s for startup health check..."

if ! wait_for_miner_ready; then
  echo "[!] AlphaPool miner failed startup health check within ${STARTUP_WAIT}s."
  [ -n "$STARTUP_HEALTH_REASON" ] && echo "    Reason: ${STARTUP_HEALTH_REASON}"
  echo "    Old session was already stopped before launch."
  echo "    Try: export STARTUP_WAIT=45"
  echo "    Log: tail -n 80 ${LOG_FILE}"
  exit 1
fi

echo "[+] Started AlphaPool PRL miner."
echo "    Health: ${STARTUP_HEALTH_REASON}"
if [ "$LAUNCH_MODE" = "screen" ]; then
  echo "    Screen: screen -r ${SESSION}"
  echo "    Detach: Ctrl+A then D"
  echo "    Stop:   screen -S ${SESSION} -X quit"
else
  echo "    Mode:   ${LAUNCH_MODE} background"
  echo "    PID:    $(cat "$PID_FILE" 2>/dev/null || true)"
  echo "    Stop:   kill \"\$(cat ${PID_FILE})\""
fi
echo "    Dir:    ${MINER_DIR}"
echo "    Log:    tail -n 80 ${LOG_FILE}"
echo "    Summary: VIEW=summary bash /tmp/start-alpha-auto.sh"
echo "    Pool:   ${POOL_URL}"
echo "    Worker: ${WORKER}"
echo "    Status: every ${STATUS_INTERVAL}s"

if [ "$KEEP_ALIVE" = "1" ]; then
  echo ""
  echo "[*] Keeping startup command alive by following a filtered miner summary."
  echo "    Press Ctrl+C to leave this view; the miner keeps running in the background."
  if tail -n 80 -F "$LOG_FILE" 2>/dev/null | filter_alpha_log; then
    :
  else
    tail -n 80 -f "$LOG_FILE" 2>/dev/null | filter_alpha_log
  fi
fi
