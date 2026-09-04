# Railway Lightning Stack - LND (Neutrino) + ThunderHub + LNbits

A self-custodial Lightning node with a management UI and wallet/API layer, deployed
on Railway. This guide walks all four phases. Read `CLAUDE.md` for the "why" and the
Railway-specific gotchas.

> Heads-up: this exact LND stack is the most involved thing to run on Railway. If it
> gets painful, `phoenixd + LNbits` is a much simpler Railway-native alternative
> (self-custodial, auto liquidity, no port 9735, no cert/macaroon sharing).

---

## Prerequisites

- A Railway account and a GitHub account.
- `curl` on your own computer (for Phase 1 wallet creation).
- Somewhere safe to write down 24 words (paper, metal backup).
- Update image tags to current stable before deploying:
  - LND: https://github.com/lightningnetwork/lnd/releases
  - ThunderHub: `apotdevin/thunderhub`
  - LNbits: `lnbits/lnbits`

---

## PHASE 1 - LND (Neutrino): deploy, create wallet, save seed, sync

### 1.1 Push LND to a GitHub repo
Put the `lnd/` folder contents (`Dockerfile`, `lnd.conf`, `start.sh`) into a repo,
or point Railway at this repo's `lnd/` directory. Edit `lnd.conf` -> set `alias`.

### 1.2 Create the Railway service
- New project -> Deploy from GitHub repo.
- **Name the service `lnd`** (so its private address is `lnd.railway.internal`,
  matching `tlsextradomain` in `lnd.conf`).
- Add a **Volume**, mount path **`/data`**.
- Deploy. In the logs LND will start and WAIT ("waiting for wallet") - expected.

### 1.3 Temporarily expose REST to create the wallet
LND REST is HTTPS with a self-signed cert, so use a **TCP Proxy** (raw passthrough),
NOT the HTTP domain. In the `lnd` service networking settings, add a **TCP Proxy for
port 8080**. Note the host:port Railway gives you (e.g. `x.proxy.rlwy.net:23456`).

### 1.4 Generate seed + create wallet (from YOUR computer)
Edit `scripts/create-wallet.sh` (set PROXY + password), then:
```
./scripts/create-wallet.sh genseed      # prints 24 words -> WRITE THEM DOWN
# paste the 24 words into SEED_WORDS in the script, then:
./scripts/create-wallet.sh initwallet   # creates + unlocks the wallet
```
Or do it by hand:
```
curl -k https://PROXY_HOST:PORT/v1/genseed
curl -k -X POST https://PROXY_HOST:PORT/v1/initwallet \
  -d '{"wallet_password":"BASE64_PW","cipher_seed_mnemonic":["w1",...,"w24"]}'
```
(`BASE64_PW` = `echo -n "your-password" | base64`)

### 1.5 Wait for sync
Watch the logs until LND reports **synced to chain** (minutes to ~1 hour).

### 1.6 Enable auto-unlock (survive restarts)
- Add Railway env var `WALLET_PASSWORD` = your plain wallet password.
- Uncomment in `lnd.conf`: `wallet-unlock-password-file=/data/walletpassword.txt`
- Commit + redeploy. `start.sh` writes the password file on boot and LND
  auto-unlocks.

**Checkpoint:** LND deployed, wallet created, SEED SAVED, synced, auto-unlock on.

---

## PHASE 2 - ThunderHub

### 2.1 Get LND's credentials as strings
- Set Railway env var `PRINT_CREDS=1` on the `lnd` service, redeploy.
- Open the logs and copy:
  - **ADMIN MACAROON (hex)**
  - **TLS CERT (base64)**
- **Remove `PRINT_CREDS`** and redeploy (don't leave creds printing to logs).

### 2.2 Configure + deploy ThunderHub
- In `thunderhub/thubConfig.yaml`, set `masterPassword`, and paste the
  `macaroon` (hex) and `certificate` (base64).
- Push `thunderhub/` to a repo (or this repo's `thunderhub/` dir).
- New Railway service from that repo. It talks to `lnd.railway.internal:10009`
  over the private network.
- Give it a **public domain** (ThunderHub listens on port 3000). Log in with your
  masterPassword.

---

## PHASE 3 - LNbits

### 3.1 Deploy LNbits
- New Railway service from image **`lnbits/lnbits:latest`**.
- Add a **Volume** at **`/app/data`**.
- Add env vars from `lnbits/.env.example`, pasting:
  - `LND_REST_MACAROON` = ADMIN MACAROON (hex)
  - `LND_REST_CERT`     = TLS CERT (hex)
- Give it a **public domain** (LNbits listens on `$PORT`, which Railway provides).

### 3.2 Verify
Open the LNbits URL, create a wallet, and check it shows your node's balance once
you have funds. (See MIGRATION.md if you are restoring LNbits data from Voltage.)

---

## PHASE 4 - Go live: p2p, security, funds

### 4.1 Open the Lightning p2p port
- Add a **TCP Proxy for port 9735** on the `lnd` service.
- Add the proxy host:port to LND as an external address (add
  `externalip=PROXY_HOST:PORT` to `lnd.conf`, redeploy). This lets peers reach you.

### 4.2 Lock it down (see SECURITY.md)
- Remove the temporary REST (8080) TCP proxy if you no longer need external REST.
- Never expose gRPC/REST publicly without need. Protect the UIs.

### 4.3 Fund + open channels
- In ThunderHub, get an on-chain address, send BTC, wait for confirmation.
- Open channels (batch-open several in one tx to save on fees). Check
  mempool.space and open when fee rates are low.

---

## Cost note
Three always-on services on Railway's usage billing typically run ~$10-20/month,
more than a flat $5 VPS. You're paying for the platform convenience.

## Backups
- 24-word seed = primary backup (offline).
- Also keep LND's `channel.backup` (Static Channel Backup) - ThunderHub can export
  it. It lets you recover channel funds if the deployment dies.
