# CLAUDE.md - Project Context

This file gives an AI assistant (or a new teammate) the context to help with this
project quickly. Read it first.

## What this project is

A self-hosted Lightning stack deployed on **Railway**:

- **LND** (Lightning node) running in **Neutrino** mode (light client - no full
  blockchain, small + cheap).
- **ThunderHub** - web UI to manage the node (channels, send/receive, fees).
- **LNbits** - wallet + API layer on top of the node (sub-wallets, invoices,
  extensions).

## Why we are building it

We are migrating a Lightning node OFF **Voltage** (managed host) because of repeated
outages and Voltage's shift toward enterprise/financial products. The goal is a
setup we control: reliable, cheap, self-custodial, and keeping ThunderHub + LNbits.

## Key decisions (and the alternatives we rejected)

- **Neutrino, not a full/pruned Bitcoin node.** Cheapest and lightest. Trade-off:
  slightly less private; not ideal for heavy routing. Fine for send/receive + LNbits.
  We can switch LND to a pruned Bitcoin Core backend later WITHOUT losing channels.
- **Railway** was chosen as the host. Note: this exact 4-part LND stack is the
  *hardest* thing to run on Railway (see constraints). A simpler alternative that
  fits Railway much better is **phoenixd + LNbits** (ACINQ's self-custodial daemon,
  auto liquidity, HTTP API, no port 9735, no cert/macaroon file-sharing). Keep this
  in mind if the LND path becomes too painful.

## Railway-specific constraints we had to design around

1. **Services can't share files.** Each Railway service has its own volume, so
   ThunderHub/LNbits cannot read LND's tls.cert/admin.macaroon from disk. We pass
   them as **hex/base64 strings** in env vars / config instead. The LND entrypoint
   (`lnd/start.sh`) can dump these to the logs when `PRINT_CREDS=1`.
2. **No easy interactive shell.** We create the LND wallet via the **REST API**
   (`/v1/genseed` then `/v1/initwallet`) over a temporary TCP proxy, which also lets
   us CAPTURE THE SEED (auto-create would hide it).
3. **Wallet locks on restart.** Railway redeploys restart the container, so we use
   **auto-unlock**: `start.sh` writes a password file from the `WALLET_PASSWORD`
   Railway secret, and `lnd.conf` points `wallet-unlock-password-file` at it.
4. **Port 9735 (Lightning p2p) needs Railway's TCP Proxy.** Without it, outbound
   channels still work; inbound connections/channels do not.
5. **The persistent volume mounts at `/data` and hides baked-in files there**, so
   config lives at `/app/lnd.conf` (outside the volume) via `--configfile`.

## Repo layout

- `lnd/`         Dockerfile + lnd.conf + start.sh (the node)
- `thunderhub/`  Dockerfile + thubConfig.yaml (management UI)
- `lnbits/`      .env.example (wallet/API layer)
- `scripts/`     create-wallet.sh (Phase 1 helper, run from your laptop)
- `README.md`    full step-by-step deployment guide (4 phases)
- `MIGRATION.md` how to move funds/channels off Voltage onto this node
- `SECURITY.md`  how to expose/lock down each service safely

## Current status / next steps

- [ ] Phase 1: Deploy LND, create wallet, SAVE SEED, sync, enable auto-unlock
- [ ] Phase 2: Deploy ThunderHub (hex macaroon + base64 cert)
- [ ] Phase 3: Deploy LNbits (hex macaroon + hex cert, REST backend)
- [ ] Phase 4: TCP proxy for 9735, lock down access, fund, open channels
- [ ] Migration: close Voltage channels, move funds, reopen here (see MIGRATION.md)

## Golden rules

- The 24-word seed is the ONLY backup of the funds. Store it offline. No one can
  recover it for you.
- Never commit secrets (.env, walletpassword, seed, macaroons). See .gitignore.
- Never expose ThunderHub/LNbits/gRPC/REST to the public internet without auth +
  TLS. Only port 9735 should face the world. See SECURITY.md.
- Update image tags to current stable versions before deploying.
