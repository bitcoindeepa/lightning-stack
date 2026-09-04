# DEPLOY.md — production runbook

The configured target. Follow the phases in order; each one depends on the last.

| Service | Source | Public? | Volume |
|---|---|---|---|
| `lnd` | `lnd/Dockerfile` | TCP proxy on 9735 only | 5 GB at `/data` |
| `thunderhub` | `thunderhub/Dockerfile` | `node.bitcoindeepa.com` | none |
| `lnbits` | `lnbits/Dockerfile` | `pay.bitcoindeepa.com` | 1 GB at `/app/data` |
| `Postgres` | Railway plugin | no | managed |

Lightning Addresses resolve as `you@bitcoindeepa.com` via a rewrite on the
existing Vercel site — the apex A record is not touched. See Phase 5.

**Service names don't control the internal hostname — Railway locks
`RAILWAY_PRIVATE_DOMAIN` to the service's slug at creation time, and renaming
the service afterward does *not* change it.** Check the actual value (Railway
dashboard → `lnd` service → Variables → `RAILWAY_PRIVATE_DOMAIN`, or
`railway variable list --service lnd`) and set `tlsextradomain` in
`lnd/lnd.conf` to match it before first boot. This deployment's actual domain
is `bitcoindeepa-lightning-stack.railway.internal` (the service was originally
created as `Bitcoindeepa-Lightning-Stack` and later renamed to `lnd`, which
only changed the display name). Every `lnd.railway.internal` reference below
must use whatever your real `RAILWAY_PRIVATE_DOMAIN` turns out to be.

---

## Phase 0 — Railway project

1. New Railway project → **Deploy from GitHub repo** →
   `CeyLabs/Bitcoindeepa-Lightning-Stack`.
2. Create **four** services from that same repo. For each one, set
   **Settings → Build → Root Directory** and Railway will pick up that folder's
   `railway.json` automatically:

   | Service name | Root Directory |
   |---|---|
   | `lnd` | `/lnd` |
   | `thunderhub` | `/thunderhub` |
   | `lnbits` | `/lnbits` |

3. Add the **Postgres** plugin to the project (`+ New` → Database → Postgres).

---

## Phase 1 — LND: deploy, create the wallet, save the seed

### 1.1 Volume

`lnd` service → **Settings → Volumes** → mount at **`/data`**, size **5 GB**.
Railway volumes can be grown later but never shrunk.

### 1.2 Variables

| Variable | Value |
|---|---|
| `WALLET_PASSWORD` | the generated wallet password — **this is not the seed, but losing it locks the node until you restore from seed** |
| `ALLOW_WALLET_CREATE` | `1` — **Phase 1 only, remove in 1.6** |
| `TELEGRAM_BOT_TOKEN` | your bot token |
| `TELEGRAM_CHAT_ID` | your chat id |

Deploy. The logs should show `wrote walletpassword.txt for auto-unlock` and LND
waiting on the wallet unlocker.

> `ALLOW_WALLET_CREATE=1` leaves LND's **unauthenticated** wallet-creation RPC
> open. It is on for one step only, behind a proxy you delete afterwards.

### 1.3 Temporary TCP proxy for REST

`lnd` → **Settings → Networking → TCP Proxy** → target port **`8080`**.
Railway returns something like `monorail.proxy.rlwy.net:23456`.

### 1.4 Create the wallet and capture the seed

From your own machine, not Railway:

```sh
export LND_PROXY="monorail.proxy.rlwy.net:23456"   # from step 1.3
./scripts/create-wallet.sh genseed
```

**Write the 24 words on paper.** They are the only backup of the funds — no one
can regenerate them for you. Then:

```sh
export WALLET_PASSWORD="<the exact value from 1.2>"
export SEED_WORDS='["word1","word2", ... ,"word24"]'
./scripts/create-wallet.sh initwallet
```

### 1.5 Dump credentials for the other services

Still on `lnd`, set `PRINT_CREDS=1` and redeploy. From the logs, copy and keep:

- **TLS CERT (hex)** → LNbits `LND_REST_CERT`
- **TLS CERT (base64)** → ThunderHub `LND_CERT_BASE64`
- **ADMIN MACAROON (hex)** → both `LND_MACAROON_HEX` / `LND_REST_MACAROON`

### 1.6 Close the door

On the `lnd` service, **delete `ALLOW_WALLET_CREATE`, delete `PRINT_CREDS`, and
delete the port-8080 TCP proxy.** Redeploy. LND now auto-unlocks on every
restart from the password file.

### 1.7 Inbound: permanent TCP proxy on 9735

Add a TCP Proxy targeting port **`9735`**. Take the host:port it gives you and
set on `lnd`:

| Variable | Value |
|---|---|
| `LND_EXTERNAL_ADDR` | `<proxy-host>:<proxy-port>` |

Redeploy. LND resolves that hostname at startup and advertises it, so other
nodes can open channels to you.

> LND resolves the proxy hostname **once, at boot**. If Railway ever changes the
> proxy's IP, redeploy `lnd` to re-advertise. Without this variable, outbound
> channels still work; inbound ones do not.

### 1.8 Wait for sync

Watch the logs for Neutrino filter-header sync. First sync takes a while. Do not
fund the node until it reports fully synced.

---

## Phase 2 — ThunderHub

Variables on the `thunderhub` service:

| Variable | Value |
|---|---|
| `THUB_MASTER_PASSWORD` | the generated ThunderHub password — this is the UI login |
| `LND_MACAROON_HEX` | admin macaroon (hex) from 1.5 |
| `LND_CERT_BASE64` | TLS cert (base64) from 1.5 |
| `THUB_ACCOUNT_NAME` | `BitcoinDeepa` (optional) |
| `LND_GRPC_HOST` | `bitcoindeepa-lightning-stack.railway.internal:10009` — **required**, no default. Must be the `lnd` service's real `RAILWAY_PRIVATE_DOMAIN`, matching `tlsextradomain`. |

`start.sh` writes `thubConfig.yaml` at boot from these. The macaroon is never
committed and never baked into the image.

---

## Phase 3 — Postgres + LNbits

### 3.1 Volume

`lnbits` → Volumes → mount at **`/app/data`**, 1 GB. Extension files and uploads
live there; wallets and balances live in Postgres.

### 3.2 Variables

Full list and comments in `lnbits/.env.example`. The one that trips people up:

```
LNBITS_DATABASE_URL=postgres://${{Postgres.PGUSER}}:${{Postgres.PGPASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{Postgres.PGDATABASE}}
```

Paste that **literally**, Railway references and all. Do **not** use
`${{Postgres.DATABASE_URL}}` — Railway emits `postgresql://` and LNbits refuses
to start on anything that is not `postgres://`.

Set the rest per `.env.example`, in particular:

| Variable | Value |
|---|---|
| `LND_REST_ENDPOINT` | `https://bitcoindeepa-lightning-stack.railway.internal:8080` |
| `LND_REST_CERT` | TLS cert **hex** from 1.5 |
| `LND_REST_MACAROON` | admin macaroon hex from 1.5 |
| `AUTH_SECRET_KEY` | the generated 64-hex value |
| `LNBITS_BASEURL` | `https://pay.bitcoindeepa.com/` |
| `LNBITS_ADMIN_UI` | `true` |

### 3.3 First boot

Open the LNbits URL, create your account. Find the **super user id** in the
service logs, then set `SUPER_USER` to it and redeploy so it survives a fresh
container.

Then close registration: put your user id in `LNBITS_ADMIN_USERS`, and list any
other permitted ids in `LNBITS_ALLOWED_USERS`. **Left empty, anyone who finds
the URL can register a wallet on your node.**

---

## Phase 4 — Domains

### 4.1 ThunderHub

`thunderhub` → Settings → Networking → **Custom Domain** →
`node.bitcoindeepa.com`. Add the CNAME Railway shows you:

```
node   CNAME   <value-railway-gives-you>
```

### 4.2 LNbits

`lnbits` → Custom Domain → `pay.bitcoindeepa.com`:

```
pay    CNAME   <value-railway-gives-you>
```

---

## Phase 5 — Lightning Addresses on the apex domain

Goal: `you@bitcoindeepa.com`, without touching the apex A record or the website.

A Lightning Address resolves exactly one URL:
`https://bitcoindeepa.com/.well-known/lnurlp/<username>`. So forward only that
path from the existing site to LNbits.

In the **website's** repo (not this one), add to `vercel.json`:

```json
{
  "rewrites": [
    {
      "source": "/.well-known/lnurlp/:username",
      "destination": "https://pay.bitcoindeepa.com/.well-known/lnurlp/:username"
    }
  ]
}
```

Netlify equivalent, in `netlify.toml`:

```toml
[[redirects]]
  from = "/.well-known/lnurlp/*"
  to = "https://pay.bitcoindeepa.com/.well-known/lnurlp/:splat"
  status = 200
  force = true
```

Use a rewrite/proxy (`status = 200`), not a 301/302 — some wallets do not follow
redirects on this path.

Verify once deployed:

```sh
curl https://bitcoindeepa.com/.well-known/lnurlp/yourname
```

You should get LNURL-pay JSON with a `callback` pointing at
`pay.bitcoindeepa.com`. A callback on a different host is correct and expected.

---

## Phase 6 — Fund and verify

1. Send a small amount of on-chain BTC to the node. Confirm it appears.
2. Open one small channel. Watch for a Telegram message with `channel.backup`
   attached — **if it does not arrive, stop and fix backups before funding
   further.** That file is the only way to recover channel funds if the Railway
   volume is lost.
3. Send and receive a test payment through LNbits.
4. Only then move real balance. For moving off Voltage, see `MIGRATION.md`.

---

## Troubleshooting

**`ECONNREFUSED fd12:...:10009` from ThunderHub or LNbits.**
Railway's private network is **IPv6-only** — `lnd.railway.internal` resolves to
an `fd12::/16` address. A service bound to `0.0.0.0` listens on IPv4 only, so
nothing is on the address the caller reaches. Everything in this stack must bind
`[::]`, never `0.0.0.0`:

- `lnd.conf` → `listen` / `rpclisten` / `restlisten` all use `[::]`
- LNbits → `LNBITS_HOST=::`

On Linux `[::]` also accepts IPv4, so it is strictly wider than `0.0.0.0`.
This applies to Railway's TCP proxy too, so port 9735 needs it for inbound.

**`no such host` for the fee URL.** `fee.url` is required for Neutrino on
mainnet and LND will not start without it. Note the key is `fee.url` under
`[fee]` — the old top-level `feeurl` is deprecated. The response must be LND's
own `{"fee_by_block_target": {...}}` shape, so a generic fee API will not work
as a drop-in replacement.

---

## Operational notes

**The seed is the only backup of on-chain funds. `channel.backup` is the only
backup of channel funds.** Neither is recoverable by anyone but you.

**Do not restore an old `channel.backup` onto a running node.** It force-closes
channels at the recorded state. It is a disaster-recovery tool, not a snapshot.

**Never regenerate LND's TLS cert casually.** `tlsdisableautofill=true` keeps the
cert stable across redeploys. If you ever do delete `tls.cert`, LND makes a new
one and both ThunderHub and LNbits break until you repeat step 1.5.

**Neutrino trade-offs.** Cheap and light, but weaker privacy and not suited to
serious routing. Swapping to a pruned Bitcoin Core backend later changes
`bitcoin.node` and adds a service — channels are not lost.

**Restart behaviour.** `lnd` uses `restartPolicyType: ALWAYS`. A node that stays
down with channels open risks force-closes by peers.
