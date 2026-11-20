<!-- markdownlint-disable-next-line MD041 -->
<br>

<a href="https://bitcoindeepa.com"><picture><source media="(prefers-color-scheme: dark)"
  srcset="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/wordmark-dark.svg"><img
  alt="Bitcoin Deepa: Pearl of Satoshi" width="260"
  src="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/wordmark.svg"></picture></a>

<p>A self-custodial Lightning node on Railway: LND, ThunderHub and LNbits.<br><strong>Runs the node behind
<a href="https://t.me/BitcoinDeepaBot">@BitcoinDeepaBot</a></strong>, open source and AGPL-3.0 licensed.</p>

<p>
<a href="https://bitcoindeepa.com"><picture><source media="(prefers-color-scheme: dark)"
  srcset="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/pill-website-dark.svg"><img
  alt="Website" height="34"
  src="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/pill-website.svg"></picture></a>
<a href="https://t.me/BitcoinDeepa"><picture><source media="(prefers-color-scheme: dark)"
  srcset="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/pill-telegram-dark.svg"><img
  alt="Telegram" height="34"
  src="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/pill-telegram.svg"></picture></a>
<a href="https://x.com/bitcoindeepa"><picture><source media="(prefers-color-scheme: dark)"
  srcset="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/pill-x-dark.svg"><img
  alt="Follow on X" height="34"
  src="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/pill-x.svg"></picture></a>
<a href="https://github.com/bitcoindeepa/lightning-stack/blob/main/LICENSE"><picture><source
  media="(prefers-color-scheme: dark)"
  srcset="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/pill-license-agpl-dark.svg"><img
  alt="License: AGPL-3.0" height="34"
  src="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/pill-license-agpl.svg"></picture></a>
<a href="https://github.com/bitcoindeepa/.github/blob/main/CONTRIBUTING.md"><picture><source
  media="(prefers-color-scheme: dark)"
  srcset="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/pill-contribute-dark.svg"><img
  alt="Contribute" height="34"
  src="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/pill-contribute.svg"></picture></a>
</p>

<br>

## What's in it

- <img width="20" height="20" alt=""
  src="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/icon-lnd.svg">
  **[LND][lnd]**: the Lightning node itself, in Neutrino (light client) mode on mainnet. Holds the keys and the channels.
- <img width="20" height="20" alt=""
  src="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/icon-thunderhub.svg">
  **[ThunderHub][thunderhub]**: the web UI for running the node. Channels, balances, forwards, fees, send and receive.
- <img width="20" height="20" alt=""
  src="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/icon-lnbits.svg">
  **[LNbits][lnbits]**: the wallet and API layer on top of LND. Sub-wallets, invoices, extensions and Lightning Addresses.
- <img width="20" height="20" alt=""
  src="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/icon-postgres.svg">
  **Postgres**: Railway's
  database plugin. Stores LNbits wallets, users and balances.
- <img width="20" height="20" alt=""
  src="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/icon-backups.svg">
  **Channel backups**:
  `lnd/start.sh` sends `channel.backup` to Telegram on startup and every time it changes.
- <img width="20" height="20" alt=""
  src="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/icon-alerts.svg">
  **Payment alerts**: the same
  script posts received and sent payments, failed sends, channel opens and closes, and node restarts to Telegram.
- <img width="20" height="20" alt=""
  src="https://raw.githubusercontent.com/bitcoindeepa/lightning-stack/main/.github/assets/readme/icon-addresses.svg">
  **Lightning Addresses**:
  `you@bitcoindeepa.com`, served by LNbits through a single rewrite on the website.

## Run it

There is no Docker Compose file. Each service folder is a Dockerfile plus a `railway.json`, deployed as its own
[Railway](https://railway.com) service. [DEPLOY.md][DEPLOY.md] is the full runbook. The short version:

1. Create a Railway project from this repo. Add three services with these root directories: `lnd` → `/lnd`,
   `thunderhub` → `/thunderhub`, `lnbits` → `/lnbits`. Add the Postgres plugin.
2. On `lnd`, mount a 5 GB volume at `/data`. Check the service's real `RAILWAY_PRIVATE_DOMAIN` and make sure it is
   listed as a `tlsextradomain` in [`lnd/lnd.conf`][lnd/lnd.conf]. Set `WALLET_PASSWORD`, `ALLOW_WALLET_CREATE=1`
   and the `TELEGRAM_*` variables, then deploy. LND waits for a wallet.
3. Add a temporary TCP proxy to port 8080 and create the wallet from your own computer, never on Railway:

   ```sh
   export LND_PROXY="<proxy-host>:<proxy-port>"
   ./scripts/create-wallet.sh genseed     # write the 24 words on paper

   export WALLET_PASSWORD="<same value as on Railway>"
   export SEED_WORDS='["word1","word2", ... ,"word24"]'
   ./scripts/create-wallet.sh initwallet
   ```

4. Set `PRINT_CREDS=1` and redeploy to print the TLS cert to the logs. Then **delete `ALLOW_WALLET_CREATE`,
   `PRINT_CREDS` and the 8080 proxy**, and redeploy. LND now unlocks itself on every restart.
5. Add a permanent TCP proxy to port 9735 and set `LND_EXTERNAL_ADDR` to its `host:port` so peers can open
   channels to you. Wait for Neutrino to finish syncing before funding anything.
6. Bake scoped macaroons for ThunderHub and LNbits (see [Keep the funds safe](#keep-the-funds-safe)).
7. **ThunderHub:** set its four required variables and give it a domain (`node.bitcoindeepa.com`).
8. **LNbits:** mount a 1 GB volume at `/app/data`, set the variables from
   [`lnbits/.env.example`][lnbits/.env.example], and give it a domain (`pay.bitcoindeepa.com`). Register, set
   `SUPER_USER`, then close registration.
9. Send a small amount, open one small channel and **check that `channel.backup` arrives in Telegram** before
   moving real balance.

- **Bind `[::]`, never `0.0.0.0`.** Railway's private network is IPv6-only, so an IPv4 bind gives `ECONNREFUSED`.
- **Cert as base64, macaroon as hex.** LNbits takes the cert in `LND_CERT_BASE64`. Do not set `LND_REST_CERT`.
- **Ports:** LND 9735 (p2p), 10009 (gRPC), 8080 (REST); LNbits 5000; ThunderHub 3000, the image default.
  Only 9735 gets a TCP proxy.
- **Cost:** three always-on services on Railway's usage billing run about $10–20 a month.

<details>
<summary><strong>Environment variables</strong></summary>

<br>

Set these in Railway, per service. None of them belong in the repo.

**`lnd`** (read by [`lnd/start.sh`][lnd/start.sh])

| Variable | What it does |
| --- | --- |
| `WALLET_PASSWORD` | Required. Written to `/data/walletpassword.txt` so LND unlocks on every restart |
| `TELEGRAM_BOT_TOKEN` | Bot that receives `channel.backup` and the payment alerts |
| `TELEGRAM_CHAT_ID` | Chat for backups and alerts. Negative for groups; supergroups take a `-100` prefix |
| `TELEGRAM_THREAD_ID` | Optional topic id in a forum group. Unset posts to General |
| `TELEGRAM_NOTIFY` | `0` turns off payment and channel alerts. The backup push always runs |
| `LND_EXTERNAL_ADDR` | `host:port` of the 9735 TCP proxy, advertised to peers |
| `ALLOW_WALLET_CREATE` | Setup only. `1` opens the unauthenticated wallet-creation RPC |
| `PRINT_CREDS` | Setup only. `1` prints the TLS cert and admin macaroon to the logs |
| `REGEN_TLS` | One-shot. `1` deletes `tls.cert` and `tls.key` so LND issues new ones |

**`thunderhub`** (read by [`thunderhub/start.sh`][thunderhub/start.sh], which writes `thubConfig.yaml` at boot)

| Variable | What it does |
| --- | --- |
| `THUB_MASTER_PASSWORD` | Required. The ThunderHub login |
| `LND_GRPC_HOST` | Required. `<lnd RAILWAY_PRIVATE_DOMAIN>:10009`, no default |
| `LND_CERT_BASE64` | Required. LND's TLS cert, base64 |
| `LND_MACAROON_HEX` | Required. Macaroon for ThunderHub, hex |
| `THUB_ACCOUNT_NAME` | Account name in the UI. Defaults to `BitcoinDeepa` |
| `ACCOUNT_CONFIG_PATH` | Set in the Dockerfile to `/tmp/thubConfig.yaml` |
| `NO_VERSION_CHECK` | Set in the Dockerfile. No upstream version pings |
| `DISABLE_LNMARKETS` | Set in the Dockerfile. Hides the LN Markets promo |

**`lnbits`** (see [`lnbits/.env.example`][lnbits/.env.example])

| Variable | What it does |
| --- | --- |
| `LNBITS_BACKEND_WALLET_CLASS` | `LndRestWallet`: fund LNbits from our LND over REST |
| `LND_REST_ENDPOINT` | `https://<lnd private domain>:8080` |
| `LND_REST_MACAROON` | Macaroon for LNbits, hex |
| `LND_CERT_BASE64` | LND's TLS cert, base64. `lnbits/start.sh` writes it to a file and sets `LND_REST_CERT` |
| `LNBITS_DATABASE_URL` | Postgres URL. Must start with `postgres://`, not `postgresql://` |
| `LNBITS_DATA_FOLDER` | `/app/data`, the volume for extensions and uploads |
| `LNBITS_HOST` | `::` (IPv6 wildcard, also accepts IPv4) |
| `LNBITS_PORT` | `5000`, the port LNbits listens on |
| `PORT` | `5000`, the port Railway routes the domain to |
| `FORWARDED_ALLOW_IPS` | `*`, trust proxy headers from Railway's edge |
| `LNBITS_BASEURL` | Public URL with trailing slash. Used for LNURLs and Lightning Address callbacks |
| `AUTH_SECRET_KEY` | 64 hex characters that sign sessions. Changing it logs everyone out |
| `LNBITS_ADMIN_UI` | `true` turns on the admin UI |
| `SUPER_USER` | Super user id, from the logs after first boot |
| `LNBITS_ALLOWED_USERS` | Who may use the instance. **Empty means anyone with the URL** |
| `LNBITS_ADMIN_USERS` | Admin user ids |
| `LNBITS_SITE_TITLE` | `BitcoinDeepa` |
| `LNBITS_SITE_TAGLINE` | Tagline on the LNbits home page |
| `LNBITS_EXTENSIONS_DEFAULT_INSTALL` | JSON list of extensions installed by default. `["lnurlp"]` for Lightning Addresses |

**`scripts/create-wallet.sh`** (on your own computer)

| Variable | What it does |
| --- | --- |
| `LND_PROXY` | `host:port` of the temporary 8080 TCP proxy |
| `WALLET_PASSWORD` | Must match the Railway secret exactly |
| `SEED_WORDS` | The 24 words as a JSON array, for `initwallet` |

</details>

## Keep the funds safe

This node holds real money and is always online. Read [SECURITY.md][SECURITY.md] in full before it holds
anything you would miss. The parts that matter most:

- **The 24-word seed is the only backup of on-chain funds.** Paper or metal, offline. No screenshots, no synced
  password manager, no chats. No one can recover it for you.
- **`channel.backup` is the only backup of channel funds.** `lnd/start.sh` checks it every 30 seconds and sends
  each new version to Telegram. LND encrypts it with a key from your seed, so it is useless without the seed.
- **Check that the backup push works** after your first channel opens. It fails silently, and you find out at
  the worst moment.
- **Never restore an old `channel.backup` onto a running node.** It force-closes channels at the recorded
  state. It is for disaster recovery only.
- **Remove the setup leftovers.** `ALLOW_WALLET_CREATE`, `PRINT_CREDS`, `REGEN_TLS` and the 8080 TCP proxy are
  each a live hole. The only TCP proxy that stays is 9735.
- **Close LNbits registration.** Set `LNBITS_ALLOWED_USERS` and `LNBITS_ADMIN_USERS` to your user id before the
  node holds a real balance. Public instances get scanned within hours.
- **Don't hand out the admin macaroon.** Bake a scoped macaroon for each service (below), so the admin macaroon
  lives only on LND's volume.
- **Never commit secrets:** `.env`, `walletpassword.txt`, the seed, `*.macaroon`, `tls.*`. See
  [`.gitignore`][.gitignore]. Anyone with Railway project access can read deploy logs, so if access changes
  hands, rebake macaroons and rotate the ThunderHub password.

What faces the internet:

- **9735 (p2p):** public on purpose, so peers can reach you.
- **LNbits:** public domain, guarded by user accounts.
- **ThunderHub:** public domain, guarded only by `THUB_MASTER_PASSWORD`. Make it long and unique. Removing its
  public domain when you don't need it is the biggest single cut in attack surface.
- **gRPC 10009, REST 8080 and Postgres:** private network only. Never give them a domain or a TCP proxy.

<details>
<summary><strong>Scoped macaroons</strong></summary>

<br>

Run these in the `lnd` container console (Railway → `lnd` → Console). `--rpcserver=[::1]:10009` is needed
because LND binds the IPv6 wildcard and `lncli` defaults to IPv4.

**LNbits:** only the endpoints LNbits' `lndrest.py` calls. It cannot spend on-chain or close channels.

```sh
lncli --lnddir=/data --rpcserver=[::1]:10009 bakemacaroon \
  invoices:read invoices:write offchain:read offchain:write
```

**ThunderHub:** full channel management, including opening and closing. `message:write` is what the Amboss
login needs.

```sh
lncli --lnddir=/data --rpcserver=[::1]:10009 bakemacaroon \
  info:read peers:read peers:write \
  onchain:read onchain:write \
  offchain:read offchain:write \
  invoices:read invoices:write \
  address:read address:write \
  message:read message:write
```

Each prints `{ "macaroon": "<hex>" }`. Put the hex in `LND_REST_MACAROON` on `lnbits` and `LND_MACAROON_HEX` on
`thunderhub`, then redeploy both.

LND gates opening and closing channels on `onchain:write`, the same permission that sends on-chain funds. So a
macaroon that can open channels can also sweep the on-chain wallet. If you don't need open and close in the UI,
drop `onchain:write`. Neither macaroon can mint new ones (`macaroon:generate`) or sign with raw keys
(`signer:generate`). `offchain:write` still lets a compromised LNbits pay invoices. This narrows the blast
radius; it does not remove it.

</details>

What no configuration fixes: there is one replica and no high availability, so Railway maintenance means
downtime. A failed payment method suspends the project, which is an outage with channels open. And while the node
is offline, nobody watches your channels. A watchtower matters more as balances grow.

## What it's made of

[LND](https://github.com/lightningnetwork/lnd) with the [Neutrino](https://github.com/lightninglabs/neutrino)
light client, [ThunderHub](https://github.com/apotdevin/thunderhub) and [LNbits](https://github.com/lnbits/lnbits),
each from its official Docker image, plus Postgres. Hosted on [Railway](https://railway.com). Small POSIX `sh`
entrypoints with `curl` and `jq` handle auto-unlock, credential hand-off, backups and Telegram alerts.

```text
lnd/
├── Dockerfile         # lightninglabs/lnd + curl, jq
├── lnd.conf           # Neutrino, listeners, TLS, fees, channels
├── start.sh           # unlock, backups, alerts, creds
└── railway.json
thunderhub/            # Dockerfile, start.sh, railway.json
lnbits/                # Dockerfile, start.sh, .env.example, railway.json
scripts/
└── create-wallet.sh   # genseed / initwallet over REST
DEPLOY.md              # production runbook
SECURITY.md            # lock-down checklist
MIGRATION.md           # moving off Voltage
```

## Node settings

From [`lnd/lnd.conf`][lnd/lnd.conf]:

- **Identity:** alias `BitcoinDeepa ⚡`, colour `#F7931A`, mainnet, `bitcoin.node=neutrino`.
- **Forwarding:** 1 sat base fee plus 200 ppm, time-lock delta 80.
- **Channels:** minimum 100,000 sats, at most 5 pending, wumbo channels and SCID aliases on, keysend and AMP
  accepted. No autopilot.
- **TLS:** `tlsdisableautofill=true` keeps the container's changing IP out of the cert, so it stays stable across
  redeploys. `tlsextradomain` lists `lnd.railway.internal` and the older
  `bitcoindeepa-lightning-stack.railway.internal`.
- **Fees:** Neutrino has no local node, so on-chain fee estimates come from `fee.url` under `[fee]`. LND will not
  start without it, and the response must be LND's own `fee_by_block_target` format.
- **Housekeeping:** cancelled invoices are cleared on startup, `channel.db` auto-compacts after 168 hours, logs
  keep 3 files of 20 MB.
- **Restarts:** `lnd` uses `restartPolicyType: ALWAYS`. A node that stays down with channels open risks
  force-closes by peers.

## Lightning Addresses

A Lightning Address only ever fetches `https://bitcoindeepa.com/.well-known/lnurlp/<username>`. The website
forwards just that path to LNbits, so the apex domain and the rest of the site stay as they are. In the
**website's** `vercel.json`:

```json
{
  "rewrites": [
    {
      "source": "/.well-known/lnurlp/:username",
      "destination":
        "https://pay.bitcoindeepa.com/.well-known/lnurlp/:username"
    }
  ]
}
```

Use a rewrite (status 200), not a 301 or 302; some wallets don't follow redirects here. Check it with
`curl https://bitcoindeepa.com/.well-known/lnurlp/yourname`: you should get LNURL-pay JSON whose `callback`
points at `pay.bitcoindeepa.com`. [DEPLOY.md][DEPLOY.md] has the Netlify version too.

## Troubleshooting

<details>
<summary><strong>Common failures and fixes</strong></summary>

<br>

- **`ECONNREFUSED fd12:…:10009` from ThunderHub or LNbits.** Something is bound to `0.0.0.0`. Railway's private
  network is IPv6-only. `lnd.conf` listeners and `LNBITS_HOST` must use `[::]` / `::`.
- **LNbits logs `[Errno 36] File name too long`, then falls back to VoidWallet.** Cert content ended up in
  `LND_REST_CERT`, which must be a file path. Unset it and set `LND_CERT_BASE64`.
- **LNbits refuses the database URL.** Railway's `${{Postgres.DATABASE_URL}}` starts with `postgresql://`. Build
  it from parts, exactly as written in [`lnbits/.env.example`][lnbits/.env.example].
- **`self-signed certificate`.** The service holds a stale cert. Reissue and re-dump (below).
- **`Hostname/IP does not match certificate's altnames`.** The cert is current but doesn't cover the hostname
  being dialled. Add it to `tlsextradomain`, then reissue.
- **`no such host` for the fee URL.** `fee.url` is required for Neutrino on mainnet. A generic fee API won't
  work; it must return LND's format.
- **Telegram `403 Bot is not a member of the group chat`.** Add the bot to the group (and make it an admin if
  posting is restricted).
- **ThunderHub's own Telegram bot fails with "Initiating subscriptions failed".** Its gRPC subscriptions break
  against this LND version. That is why `lnd/start.sh` sends the alerts instead.

**Reissuing the TLS cert.** Changing `tlsextradomain` does not reissue an existing cert.

1. On `lnd`, set `REGEN_TLS=1` and redeploy.
2. Remove `REGEN_TLS`, set `PRINT_CREDS=1`, redeploy, and copy the new base64 cert.
3. Update `LND_CERT_BASE64` on both `thunderhub` and `lnbits`. Macaroons don't change.
4. Remove `PRINT_CREDS` and redeploy.

Leaving `REGEN_TLS` set issues a new cert on every restart and breaks both services each time.

</details>

## Why it's built this way

We moved this node off [Voltage](https://voltage.cloud), a managed host, after repeated outages. The aim is a node
we control: self-custodial, cheap, and still with ThunderHub and LNbits.

- **Neutrino, not a full node.** Cheapest and lightest. It is a little less private and not meant for serious
  routing. LND can move to a pruned Bitcoin Core backend later without losing channels.
- **Railway's limits shaped the scripts.** Services can't share files, so the cert and macaroons travel as
  hex/base64 variables. There is no easy shell, so the wallet is created over REST, which also lets you see the
  seed. Redeploys restart the container, so the wallet auto-unlocks from a password file. The volume hides
  anything baked into `/data`, so config lives at `/app/lnd.conf`.
- **A simpler option exists.** If this LND setup gets painful, phoenixd plus LNbits fits Railway better: still
  self-custodial, automatic liquidity, no port 9735 and no cert or macaroon sharing.

Moving channels and funds over from Voltage, including LNbits wallet data, is covered in
[MIGRATION.md][MIGRATION.md]. Channels can't be moved between hosts: you close, move the on-chain funds, and
reopen here.

## Help out

Spot a mistake in the runbook or a gap in the hardening? Read the
[contributing guide](https://github.com/bitcoindeepa/.github/blob/main/CONTRIBUTING.md), then open an issue or
say hello on [Telegram](https://t.me/BitcoinDeepa). Security problems go through the
[security policy](https://github.com/bitcoindeepa/.github/blob/main/SECURITY.md), not a public issue.

## Licence

[AGPL-3.0](https://github.com/bitcoindeepa/lightning-stack/blob/main/LICENSE): use,
study, change and share this code. If you run a changed version for other people, including as a web
service, you share your source under the same licence.

LND, ThunderHub and LNbits are separate projects under their own licences.

The Bitcoin Deepa name, "Pearl of Satoshi", the Yaka mask, the දීප glyph and the logos are
trademarks and not covered by the code licence. See
[TRADEMARK](https://github.com/bitcoindeepa/.github/blob/main/TRADEMARK.md) and the
[brand guidelines](https://bitcoindeepa.com/brand).

<br>

<p><sub>Bitcoin Deepa · Colombo, Sri Lanka 🇱🇰 ·
<a href="mailto:hello@bitcoindeepa.com">hello@bitcoindeepa.com</a></sub></p>

[.gitignore]: https://github.com/bitcoindeepa/lightning-stack/blob/main/.gitignore
[DEPLOY.md]: https://github.com/bitcoindeepa/lightning-stack/blob/main/DEPLOY.md
[MIGRATION.md]: https://github.com/bitcoindeepa/lightning-stack/blob/main/MIGRATION.md
[SECURITY.md]: https://github.com/bitcoindeepa/lightning-stack/blob/main/SECURITY.md
[lnbits]: https://github.com/bitcoindeepa/lightning-stack/blob/main/lnbits/
[lnbits/.env.example]: https://github.com/bitcoindeepa/lightning-stack/blob/main/lnbits/.env.example
[lnd]: https://github.com/bitcoindeepa/lightning-stack/blob/main/lnd/
[lnd/lnd.conf]: https://github.com/bitcoindeepa/lightning-stack/blob/main/lnd/lnd.conf
[lnd/start.sh]: https://github.com/bitcoindeepa/lightning-stack/blob/main/lnd/start.sh
[thunderhub]: https://github.com/bitcoindeepa/lightning-stack/blob/main/thunderhub/
[thunderhub/start.sh]: https://github.com/bitcoindeepa/lightning-stack/blob/main/thunderhub/start.sh
