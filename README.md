# PRL One-Command Miner Scripts

This folder contains one-command startup scripts for mining Pearl (PRL) on AlphaPool and Pearlhash.

The scripts will:

- Install `screen` and `curl` when missing.
- Test pool endpoints and choose a reachable node when supported.
- Download the latest miner before switching pools.
- Stop the old pool `screen` session only after the new miner is downloaded.
- Run the miner in a detached `screen` session so it keeps running after SSH disconnects.
- Optionally keep the startup command alive by following a filtered miner summary.
- Prevent duplicate miner sessions for the same pool.

## Files

- `start-alpha-auto.sh` - start AlphaPool and stop the old Pearlhash session named `prl` if it is running.
- `start-pearlhash-auto.sh` - start Pearlhash and stop the old AlphaPool session named `prl-alpha` if it is running.

## GitHub Raw URLs

```bash
https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh
https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-pearlhash-auto.sh
```

## Start AlphaPool

```bash
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

Default screen session: `prl-alpha`

## Start Pearlhash

```bash
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-pearlhash-auto.sh -o /tmp/start-pearlhash-auto.sh && bash /tmp/start-pearlhash-auto.sh
```

Default screen session: `prl`

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

AlphaPool status lines are printed every 60 seconds by default. To change that:

```bash
export STATUS_INTERVAL="30"
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

## View Live Miner Output

AlphaPool:

```bash
screen -r prl-alpha
```

AlphaPool screen output is raw miner output. Full raw output is also written to `~/alpha-miner/alpha-miner.log`.

One-shot AlphaPool summary. This filters the last log lines once and exits; it does not keep following the miner:

```bash
VIEW=summary bash /tmp/start-alpha-auto.sh
```

Pearlhash:

```bash
screen -r prl
```

Pearlhash screen output is also filtered. Full raw output is written to `~/prl-miner/pearl-miner.log`.

Detach without stopping the miner:

```text
Ctrl+A then D
```

By default, the script exits after starting the background `screen` session. The miner keeps running in `screen`.

If your cloud order/startup platform requires the startup command to stay alive, enable the foreground filtered summary explicitly. With AlphaPool, the miner writes status lines every `STATUS_INTERVAL` seconds, so the filtered summary normally prints hashrate once per minute.

```bash
export KEEP_ALIVE=1
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

To leave that foreground summary manually, press `Ctrl+C`. The miner keeps running in `screen`.

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

Pearlhash:

```bash
screen -S prl -X quit
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
