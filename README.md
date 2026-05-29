# AlphaPool PRL One-Command Miner

This folder contains a one-command startup script for mining Pearl (PRL) on AlphaPool.

The script will:

- Install `screen` and `curl` when missing.
- Stop the old P-pool `screen` session named `prl` if it is running.
- Test all AlphaPool endpoints and choose the fastest reachable node.
- Download the latest `alpha-miner` every time it starts.
- Run the miner in a detached `screen` session so it keeps running after SSH disconnects.
- Prevent duplicate AlphaPool miner sessions.

## Files

- `start-alpha-auto.sh` - main startup script.

## GitHub Raw URL

```bash
https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh
```

## One-Command Start

On a new Linux mining server, run:

```bash
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

## Use A Different Wallet

The script has a default wallet inside it. To override it without editing the file:

```bash
export WALLET="your_prl_wallet_address"
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

## Optional Static Difficulty

Leave this empty unless you know you need it.

Example:

```bash
export DIFFICULTY="524288"
curl -fsSL https://raw.githubusercontent.com/lwx25799/alpha-prl/main/start-alpha-auto.sh -o /tmp/start-alpha-auto.sh && bash /tmp/start-alpha-auto.sh
```

## View Live Miner Output

```bash
screen -r prl-alpha
```

The screen view is filtered to show hashrate, pool-side/effective hashrate, connection status, and errors.

Detach without stopping the miner:

```text
Ctrl+A then D
```

## Stop Mining

```bash
screen -S prl-alpha -X quit
```

## View Log

```bash
tail -f ~/alpha-miner/alpha-miner.log
```

This file keeps the complete raw miner output.

## Notes

- The miner requires a Linux x86_64 server with a supported NVIDIA GPU and working NVIDIA driver.
- AlphaPool PPLNS uses port `5566`.
- The script tests `us1`, `us2`, `eu1`, `eu2`, `ru1`, and `sg1`, then uses the fastest reachable endpoint.
