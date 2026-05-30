#!/usr/bin/env bash
set -euo pipefail

# Fetch and run a miner startup script without curl.
# Usage:
#   bash bootstrap-run.sh alpha
#   bash bootstrap-run.sh pearlhash
#
# If this file itself is not on the server yet, bootstrap with wget or python:
#   wget -O /tmp/bootstrap-run.sh https://raw.githubusercontent.com/lwx25799/alpha-prl/main/bootstrap-run.sh
#   bash /tmp/bootstrap-run.sh alpha

GITHUB="${GITHUB:-https://raw.githubusercontent.com/lwx25799/alpha-prl/main}"
POOL="${1:-alpha}"
OUT="/tmp/start-${POOL}-auto.sh"

case "$POOL" in
  alpha|alphapool|a)
    SCRIPT_URL="${GITHUB}/start-alpha-auto.sh"
    OUT="/tmp/start-alpha-auto.sh"
    ;;
  pearl|pearlhash|p)
    SCRIPT_URL="${GITHUB}/start-pearlhash-auto.sh"
    OUT="/tmp/start-pearlhash-auto.sh"
    ;;
  *)
    echo "[!] Unknown pool: ${POOL}"
    echo "    Usage: bash bootstrap-run.sh [alpha|pearlhash]"
    exit 1
    ;;
esac

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

fetch_script() {
  local url="$1"
  local output="$2"
  local tmp="${output}.part.$$"

  if command -v curl >/dev/null 2>&1; then
    echo "[*] Fetching script with curl..."
    curl -fL --retry 3 --connect-timeout 15 --max-time 120 "$url" -o "$tmp" \
      || curl -kLf --retry 3 --connect-timeout 15 --max-time 120 "$url" -o "$tmp"
  elif command -v wget >/dev/null 2>&1; then
    echo "[*] curl not found; fetching script with wget..."
    wget -q --tries=3 --timeout=30 -O "$tmp" "$url" \
      || wget --tries=3 --timeout=30 -O "$tmp" "$url" \
      || wget --no-check-certificate --tries=3 --timeout=30 -O "$tmp" "$url"
  elif command -v busybox >/dev/null 2>&1 && busybox wget --help >/dev/null 2>&1; then
    echo "[*] curl not found; fetching script with busybox wget..."
    busybox wget -O "$tmp" "$url"
  elif command -v python3 >/dev/null 2>&1; then
    echo "[*] curl not found; fetching script with python3..."
    python_download python3 "$url" "$tmp"
  elif command -v python >/dev/null 2>&1; then
    echo "[*] curl not found; fetching script with python..."
    python_download python "$url" "$tmp"
  elif command -v node >/dev/null 2>&1; then
    echo "[*] curl not found; fetching script with node..."
    node - "$url" "$tmp" <<'JS'
const fs = require("fs");
const https = require("https");
const http = require("http");
const url = process.argv[2];
const output = process.argv[3];
const client = url.startsWith("https:") ? https : http;
client.get(url, { timeout: 60000 }, (response) => {
  if (response.statusCode !== 200) {
    console.error(`HTTP ${response.statusCode}`);
    process.exit(1);
  }
  const file = fs.createWriteStream(output);
  response.pipe(file);
  file.on("finish", () => file.close());
}).on("error", (err) => {
  console.error(err.message);
  process.exit(1);
});
JS
  else
    echo "[!] No downloader found to fetch ${url}."
    echo "    Install wget or python3, upload the script manually, or run one of:"
    echo "    wget -O ${output} ${url}"
    echo "    python3 - <<'PY'"
    echo "from urllib.request import urlretrieve"
    echo "urlretrieve('${url}', '${output}')"
    echo "PY"
    exit 1
  fi

  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    echo "[!] Download failed or returned an empty file: ${url}"
    exit 1
  fi

  mv -f "$tmp" "$output"
  chmod +x "$output"
}

fetch_script "$SCRIPT_URL" "$OUT"
echo "[+] Running ${OUT}"
exec bash "$OUT"
