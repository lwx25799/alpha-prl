# PRL One-Command Miner Scripts

This folder contains one-command startup scripts for mining Pearl (PRL) on AlphaPool and Pearlhash.

The scripts will:

- Install `screen` and `curl` when missing and sudo/root is available.
- Work without sudo by falling back to user-space downloaders and background launch modes.
- Download with `curl`, `wget`, BusyBox `wget`, `python3`, `python`, or `node`.
- Do not require `curl`; if it is missing, the script prints which fallback downloader is used.
- Probe pool endpoints with `curl`, bash `/dev/tcp`, `nc`, or Python sockets.
- Pick a writable miner directory automatically when `$HOME` is read-only.
- Test pool endpoints and choose a reachable node when supported.
- Download the latest miner before switching pools, or reuse an existing binary with `SKIP_DOWNLOAD=1`.
- Stop the old pool session only after the new miner is downloaded and verified.
- Run the miner in `screen`, `setsid`, `nohup`, or plain background mode depending on what the server has.
- Show a filtered miner summary in `screen` while keeping the full raw miner log on disk. In background modes, read the raw log directly.
- Optionally keep the startup command alive by following the same filtered summary.
- Prevent duplicate miner sessions for the same pool.

## Files

- `start-alpha-auto.sh` - start AlphaPool and stop the old Pearlhash session named `prl` if it is running.
- `start-pearlhash-auto.sh` - start Pearlhash and stop the old AlphaPool session named `prl-alpha` if it is running.
- `bootstrap-run.sh` - fetch either startup script without `curl` and run it immediately.

## GitHub Raw URLs

```bash
https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh
https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-pearlhash-auto.sh
https://raw.githubusercontent.com/lwx25799/alpha-prl/main/bootstrap-run.sh
```

## Start AlphaPool

With `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

Without `curl` (wget):

```bash
wget -O /tmp/bootstrap-run.sh https://raw.githubusercontent.com/lwx25799/alpha-prl/main/bootstrap-run.sh && bash /tmp/bootstrap-run.sh alpha
```

Without `curl` (python3):

```bash
python3 - <<'PY'
from urllib.request import urlretrieve
urlretrieve("https://raw.githubusercontent.com/lwx25799/alpha-prl/main/bootstrap-run.sh", "/tmp/bootstrap-run.sh")
PY
bash /tmp/bootstrap-run.sh alpha
```

Default screen session: `prl-alpha`

## Start AlphaPool Without curl

If the machine has no `curl`, use one of these to fetch the script first.

With `wget`:

```bash
wget -O /tmp/start-alpha-auto.sh https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh
bash /tmp/start-alpha-auto.sh
```

With BusyBox `wget`:

```bash
busybox wget -O /tmp/start-alpha-auto.sh https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh
bash /tmp/start-alpha-auto.sh
```

With Python:

```bash
python3 - <<'PY'
from urllib.request import urlretrieve
urlretrieve("https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh", "/tmp/start-alpha-auto.sh")
PY
bash /tmp/start-alpha-auto.sh
```

If only `python` exists:

```bash
python - <<'PY'
try:
    from urllib.request import urlretrieve
except ImportError:
    from urllib import urlretrieve
urlretrieve("https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh", "/tmp/start-alpha-auto.sh")
PY
bash /tmp/start-alpha-auto.sh
```

## Start Pearlhash

With `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-pearlhash-auto.sh -o /tmp/start-pearlhash-auto.sh && bash /tmp/start-pearlhash-auto.sh
```

Without `curl`:

```bash
wget -O /tmp/bootstrap-run.sh https://raw.githubusercontent.com/lwx25799/alpha-prl/main/bootstrap-run.sh && bash /tmp/bootstrap-run.sh pearlhash
```

Default screen session: `prl`

## Start Pearlhash Without curl

With `wget`:

```bash
wget -O /tmp/start-pearlhash-auto.sh https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-pearlhash-auto.sh
bash /tmp/start-pearlhash-auto.sh
```

With BusyBox `wget`:

```bash
busybox wget -O /tmp/start-pearlhash-auto.sh https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-pearlhash-auto.sh
bash /tmp/start-pearlhash-auto.sh
```

With Python:

```bash
python3 - <<'PY'
from urllib.request import urlretrieve
urlretrieve("https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-pearlhash-auto.sh", "/tmp/start-pearlhash-auto.sh")
PY
bash /tmp/start-pearlhash-auto.sh
```

If only `python` exists:

```bash
python - <<'PY'
try:
    from urllib.request import urlretrieve
except ImportError:
    from urllib import urlretrieve
urlretrieve("https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-pearlhash-auto.sh", "/tmp/start-pearlhash-auto.sh")
PY
bash /tmp/start-pearlhash-auto.sh
```

If the machine has no `curl`, `wget`, BusyBox, Python, or Node, upload the script through the provider console or file manager, then run `bash start-alpha-auto.sh` or `bash start-pearlhash-auto.sh`.

Once the startup script is on the server, miner downloads also work without `curl`. The script will print something like:

```text
[*] curl not found; using wget for downloads.
```

If outbound downloads are blocked entirely:

```bash
export SKIP_DOWNLOAD=1
bash start-alpha-auto.sh
```

## Switching Behavior

When switching pools, the target script first downloads the miner and prepares the launch command. After that it stops the old pool session, then starts the new pool session.

This avoids running two miners at the same time. There may be a short mining gap while the old process stops and the new one starts.

## Use A Different Wallet

Both scripts have a default wallet inside them. To override it without editing the file:

```bash
export WALLET="your_prl_wallet_address"
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

Use the Pearlhash command instead if you are starting Pearlhash.

## Optional Worker Name

```bash
export WORKER="rig-01"
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

## AlphaPool Options

Optional static difficulty:

```bash
export DIFFICULTY="524288"
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

Official AlphaPool starting points:

| Card class | `DIFFICULTY` |
| --- | ---: |
| V100 / CMP 100-210 | `4096` |
| RTX 2070 / 2080 | `16384` |
| RTX 3060 Ti / 3070 | `131072` |
| RTX 3080 / 3090 / CMP 70HX/90HX | `262144` |
| A100 / data-center Ampere | `131072` |
| RTX 4070 / 4080 | `262144` |
| RTX 4090 / 5080 | `524288` |
| RTX 5090 / H100 / H200 / B100 | `1048576` |

Static difficulty is useful when VarDiff climbs too slowly on high-hashrate or mixed-card rigs. A wrong value only makes pool-side stats bumpier; it does not cap GPU power or lose valid shares.

AlphaPool status lines are printed every 5 seconds by default. To change that:

```bash
export STATUS_INTERVAL="10"
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

Optional GPU selection:

```bash
export DEVICES="0,1,2"
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

Optional endpoint selection:

```bash
export POOL_ENDPOINT="sg1.alphapool.tech:5566"
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

By default, AlphaPool tests `us1`, `us2`, `eu1`, `eu2`, `ru1`, and `sg1` three times each, then uses the endpoint with the best median TCP connect time.

To change the precision:

```bash
export ENDPOINT_TESTS="5"
export ENDPOINT_TIMEOUT="3"
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

## Pearlhash Options

Pearlhash defaults to automatic endpoint selection between:

- `84.32.220.219:9000` - EU / US
- `129.226.55.135:9000` - Asia

You can force a region:

```bash
export POOL_ENDPOINT="asia"
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-pearlhash-auto.sh -o /tmp/start-pearlhash-auto.sh && bash /tmp/start-pearlhash-auto.sh
```

Accepted aliases are `eu-us`, `eu`, `us`, `asia`, `cn`, and `china`.

Pearlhash endpoint probing uses the same fallback chain as AlphaPool. To probe each endpoint multiple times:

```bash
export ENDPOINT_TESTS="3"
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-pearlhash-auto.sh -o /tmp/start-pearlhash-auto.sh && bash /tmp/start-pearlhash-auto.sh
```

## Restricted Servers (No sudo)

These scripts are designed to run on rented GPU boxes, containers, and minimal cloud images where you may not have `sudo`, `screen`, or `curl`.

What happens automatically:

| Missing tool | Fallback |
| --- | --- |
| `sudo` | Skip package install; use fallbacks below |
| `curl` | `wget`, BusyBox `wget`, `python3`, `python`, or `node` |
| `screen` | `setsid`, then `nohup`, then plain `background` |
| `/dev/tcp` | `curl`, `nc`, or Python socket probe |
| writable `$HOME` | `/tmp/alpha-miner-$UID` or `/tmp/prl-miner-$UID` |
| `tee` | Write directly to the log file |
| `tail -F` | Use `tail -f` for `KEEP_ALIVE=1` |

Recommended settings for cloud startup commands that must stay alive and have no sudo:

```bash
export WALLET="your_prl_wallet_address"
export KEEP_ALIVE=1
export STARTUP_WAIT=30
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

If outbound downloads are blocked but you can upload files through the provider console:

```bash
export WALLET="your_prl_wallet_address"
export SKIP_DOWNLOAD=1
export MINER_DIR="/tmp/alpha-miner"
bash /path/to/uploaded/start-alpha-auto.sh
```

Upload the miner binary to `${MINER_DIR}/alpha-miner` or `${MINER_DIR}/pearl-miner` before running with `SKIP_DOWNLOAD=1`.

Force a specific background launch mode when auto-detection is not what you want:

```bash
export LAUNCH_MODE="setsid"
```

Valid values are `auto`, `screen`, `setsid`, `nohup`, and `background`.

If the miner needs more than the default 30 seconds to initialize on slow hosts:

```bash
export STARTUP_WAIT=45
```

Use a custom writable directory when the default location is not suitable:

```bash
export MINER_DIR="/tmp/my-miner"
```

## View Live Miner Output

AlphaPool:

```bash
screen -r prl-alpha
```

AlphaPool screen output is filtered to show each GPU hashrate, total hashrate, and errors only. Full raw output is still written to `~/alpha-miner/alpha-miner.log`.

One-shot AlphaPool summary. This filters the last log lines once and exits; it does not keep following the miner:

```bash
VIEW=summary bash /tmp/start-alpha-auto.sh
```

Pearlhash:

```bash
screen -r prl
```

Pearlhash screen output is also filtered to show its native `Hashrate GPU #N = ...` and `Hashrate Total = ...` lines plus errors only. Full raw output is written to `~/prl-miner/pearl-miner.log`.

Detach without stopping the miner:

```text
Ctrl+A then D
```

By default, the script exits after starting the background `screen` session. The miner keeps running in `screen`.

If `screen` is unavailable and sudo/root cannot install it, the script starts the miner in a background mode instead (`setsid`, `nohup`, or plain background). In that mode, use the PID file to stop it:

```bash
kill "$(cat ~/alpha-miner/prl-alpha.pid)"
kill "$(cat ~/prl-miner/prl.pid)"
```

If your cloud order/startup platform requires the startup command to stay alive, enable the foreground filtered summary explicitly. With AlphaPool, the miner writes status lines every `STATUS_INTERVAL` seconds, so the filtered summary normally prints hashrate every 5 seconds by default.

```bash
export KEEP_ALIVE=1
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

To leave that foreground summary manually, press `Ctrl+C`. The miner keeps running in the background.

If your platform shows `^C` instead of exiting, it is not sending an interrupt to the script. Close the terminal or start the script without `KEEP_ALIVE=1`.

```bash
export KEEP_ALIVE=0
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

## Stop Mining

AlphaPool:

```bash
screen -S prl-alpha -X quit
```

AlphaPool in `nohup` mode:

```bash
kill "$(cat ~/alpha-miner/prl-alpha.pid)"
```

Pearlhash:

```bash
screen -S prl -X quit
```

Pearlhash in `nohup` mode:

```bash
kill "$(cat ~/prl-miner/prl.pid)"
```

## View Logs

AlphaPool:

```bash
tail -n 80 ~/alpha-miner/alpha-miner.log
```

If you need a live raw log view that exits automatically:

```bash
timeout 10s tail -f ~/alpha-miner/alpha-miner.log
```

Pearlhash:

```bash
tail -n 80 ~/prl-miner/pearl-miner.log
```

## Notes

- The miner requires a Linux x86_64 server with a supported NVIDIA GPU and working NVIDIA driver.
- AlphaPool PPLNS uses port `5566`.
- Pearlhash uses port `9000`.
