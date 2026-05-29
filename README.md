# PRL One-Command Miner Scripts

This folder contains one-command startup scripts for mining Pearl (PRL) on AlphaPool and Pearlhash.

The scripts will:

- Install `screen` and `curl` when missing.
- Test pool endpoints and choose a reachable node when supported.
- Download the latest miner before switching pools.
- Stop the old pool `screen` session only after the new miner is downloaded.
- Run the miner in a detached `screen` session so it keeps running after SSH disconnects.
- Keep the startup command alive by following the same filtered miner summary shown in `screen`, which helps cloud order/startup platforms avoid treating the job as finished immediately.
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

AlphaPool screen output is a short summary view. Full raw output is written to `~/alpha-miner/alpha-miner.log`.

Pearlhash:

```bash
screen -r prl
```

Pearlhash screen output is also filtered. Full raw output is written to `~/prl-miner/pearl-miner.log`.

Detach without stopping the miner:

```text
Ctrl+A then D
```

If you launched the script from a cloud order/startup command, it will also keep printing the filtered miner summary in the foreground. This is intentional. It prevents platforms that watch the main command from marking the order as finished right after the background `screen` session starts.

To leave that foreground log view manually, press:

```text
Ctrl+C
```

The miner keeps running in `screen`.

If you want the old behavior where the script exits immediately after starting the background miner:

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
tail -f ~/alpha-miner/alpha-miner.log
```

Pearlhash:

```bash
tail -f ~/prl-miner/pearl-miner.log
```

## Notes

- The miner requires a Linux x86_64 server with a supported NVIDIA GPU and working NVIDIA driver.
- AlphaPool PPLNS uses port `5566`.
- Pearlhash uses port `9000`.
