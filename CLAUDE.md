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

- `lnd/`         Dockerfile + lnd.conf + start.sh + railway.json (the node)
- `thunderhub/`  Dockerfile + start.sh + railway.json (management UI). start.sh
                 generates thubConfig.yaml at boot from env vars, so the admin
                 macaroon is never committed or baked into the image.
- `lnbits/`      Dockerfile + .env.example + railway.json (wallet/API layer)
- `scripts/`     create-wallet.sh (Phase 1 helper, run from your laptop)
- `DEPLOY.md`    the production runbook — follow this to deploy
- `README.md`    background + original step-by-step guide
- `MIGRATION.md` how to move funds/channels off Voltage onto this node
- `SECURITY.md`  how to expose/lock down each service safely

## Production configuration (decided 2026-09-04)

- Node alias `BitcoinDeepa ⚡`, color `#F7931A`, mainnet Neutrino.
- Forwarding policy: 1 sat base + 200 ppm, `minchansize` 100k sats, no autopilot.
- Inbound enabled: Railway TCP Proxy on 9735, advertised via `LND_EXTERNAL_ADDR`.
- LNbits on Railway Postgres (NOT SQLite), `LndRestWallet` backend.
- ThunderHub at `node.bitcoindeepa.com`, LNbits at `pay.bitcoindeepa.com`.
- Lightning Addresses are `you@bitcoindeepa.com`: the apex A record stays with
  the existing Vercel site, which rewrites only `/.well-known/lnurlp/*` to
  `pay.bitcoindeepa.com`. Nothing about the website changes otherwise.
- `channel.backup` is auto-pushed to Telegram by `lnd/start.sh` on every change.
- Pinned images: lnd `v0.21.3-beta`, lnbits `v1.6.0`, thunderhub `0.19.0`.

Three things that will silently break the stack if changed:
- **Railway's private network is IPv6-only.** Every service must bind `[::]`,
  never `0.0.0.0` — `0.0.0.0` is IPv4-only, so callers reaching the service over
  `*.railway.internal` (an `fd12::/16` address) get ECONNREFUSED. This bit us on
  LND's `rpclisten` once already.
- LND's TLS cert `tlsextradomain` (in `lnd/lnd.conf`) must exactly match the
  `lnd` service's actual `RAILWAY_PRIVATE_DOMAIN`. Railway locks that domain to
  the service's slug at creation time — renaming the service in the dashboard
  does NOT change it, so don't assume naming the service `lnd` gets you
  `lnd.railway.internal`. This deployment's real domain is
  `bitcoindeepa-lightning-stack.railway.internal` (service was created as
  `Bitcoindeepa-Lightning-Stack`, later renamed to `lnd` — display name only).
- `LNBITS_DATABASE_URL` must start with `postgres://`. Railway's
  `${{Postgres.DATABASE_URL}}` starts with `postgresql://` and LNbits refuses it,
  so the URL is assembled from `${{Postgres.PGUSER}}` etc. See DEPLOY.md.

## Current status / next steps

- [x] Phase 0: Stack configured for production (this repo)
- [x] Phase 1: Deploy LND, create wallet, SAVE SEED, sync, close creation RPC
- [ ] Phase 2: Deploy ThunderHub (hex macaroon + base64 cert)
- [ ] Phase 3: Deploy Postgres + LNbits (hex macaroon + hex cert, REST backend)
- [ ] Phase 4: Custom domains + Vercel apex rewrite for Lightning Addresses
- [ ] Phase 5: Fund, open channels, VERIFY the Telegram backup fires
- [ ] Migration: close Voltage channels, move funds, reopen here (see MIGRATION.md)

## Golden rules

- The 24-word seed is the ONLY backup of the funds. Store it offline. No one can
  recover it for you.
- Never commit secrets (.env, walletpassword, seed, macaroons). See .gitignore.
- Never expose ThunderHub/LNbits/gRPC/REST to the public internet without auth +
  TLS. Only port 9735 should face the world. See SECURITY.md.
- Update image tags to current stable versions before deploying.
