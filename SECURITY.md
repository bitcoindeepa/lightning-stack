# SECURITY.md — exposure and lock-down

The node holds real funds and is always online. This is the hardening checklist,
ordered by how much damage the gap actually allows.

## 1. Phase-1 leftovers — remove these first

Each of these is a live hole, not a theoretical one. Check the `lnd` service's
Variables tab and delete any that are still set:

| Variable / setting | Why it must go |
|---|---|
| `ALLOW_WALLET_CREATE` | Leaves LND's **unauthenticated** wallet-creation RPC open |
| `PRINT_CREDS` | Dumps the admin macaroon into the deploy logs on every restart |
| `REGEN_TLS` | Issues a new TLS cert every boot, breaking both other services |
| TCP proxy on **8080** | Publishes LND's REST API to the internet. Delete the proxy itself, not just the variable |

The only TCP proxy that should remain is **9735**.

## 2. Close LNbits registration

Left empty, anyone who finds the URL can register a wallet on your node. Public
instances get scanned within hours — expect probes of `/admin`, `/lndhub` and
the OAuth endpoints.

```
LNBITS_ALLOWED_USERS=<your user id>
LNBITS_ADMIN_USERS=<your user id>
```

Get your user id from the LNbits UI once registered. Set both before the node
holds meaningful balance.

## 3. Stop handing out the admin macaroon

The admin macaroon can open and close channels and spend the on-chain wallet.
Neither service needs that much, and LNbits — public domain, public
registration, biggest attack surface — needs very little.

Run these in the `lnd` container console (Railway → `lnd` → Console).

`--rpcserver=[::1]:10009` is required: LND binds the IPv6 wildcard and this
container enforces IPv6-only on that socket, so `lncli`'s default IPv4
`127.0.0.1` is refused. The same applies to every other `lncli` command.

**LNbits** — derived from the only endpoints `lnbits/wallets/lndrest.py` calls
(`/v1/balance/channels`, `/v1/invoices*`, `/v2/invoices/*`, `/v2/router/*`).
Cannot spend on-chain, cannot close channels:

```sh
lncli --lnddir=/data --rpcserver=[::1]:10009 bakemacaroon \
  invoices:read invoices:write offchain:read offchain:write
```

**ThunderHub** — needs channel management, but not `macaroon:generate` (cannot
mint further macaroons) or `onchain:write` (cannot send your on-chain funds):

```sh
lncli --lnddir=/data --rpcserver=[::1]:10009 bakemacaroon \
  info:read onchain:read offchain:read offchain:write \
  invoices:read invoices:write address:read address:write \
  peers:read peers:write signer:read
```

Each prints `{ "macaroon": "<hex>" }`. Put the hex in `LND_REST_MACAROON`
(lnbits) and `LND_MACAROON_HEX` (thunderhub), then redeploy both.

After swapping both services over, the admin macaroon should exist only on the
volume — held by no service, pasted into no variable.

Worth being honest about the residual risk: `offchain:write` still lets a
compromised LNbits *pay invoices*, so channel balance is reachable. It is a
reduction in blast radius, not an elimination.

## 4. What faces the public internet

| Port / service | Exposure | Notes |
|---|---|---|
| 9735 (p2p) | **Public, intended** | Peers must reach it to open channels |
| LNbits | Public domain | Guarded by user accounts — see §2 |
| ThunderHub | Public domain | Guarded only by `masterPassword`. Make it long and unique |
| gRPC 10009, REST 8080 | **Private network only** | Never give these a public domain or TCP proxy |
| Postgres | Private network only | Never expose |

If you do not need ThunderHub reachable from anywhere, removing its public
domain and reaching it only when required is the single biggest reduction in
attack surface available here.

## 5. Credential hygiene

- Never commit `.env`, `walletpassword.txt`, the seed, or any `*.macaroon` /
  `tls.*`. See `.gitignore`.
- Anyone with Railway project access can read deploy logs. The macaroon was
  printed there during setup — if project access ever changes hands, rebake
  macaroons and rotate the ThunderHub password.
- Changing `tlsextradomain` does not reissue the cert. Use `REGEN_TLS=1` once,
  then remove it, then re-dump with `PRINT_CREDS=1` and remove that too.

## 6. Backups

- **24-word seed**: offline, on paper or metal. The only backup of on-chain funds.
- **channel.backup**: auto-pushed to Telegram by `lnd/start.sh` on every change.
  The file is encrypted by LND with a key derived from your seed, so storing it
  in a chat is acceptable — it is useless to anyone without the seed.
- Verify the Telegram push actually fires after a channel opens. It is silent
  when broken, and you find out at the worst possible moment.
- **Never restore an old `channel.backup` onto a running node.** It force-closes
  channels at the recorded state. Disaster recovery only.

## 7. What no configuration can fix

- Single replica, no HA. Railway maintenance means downtime.
- A failed payment method suspends the project — an outage with channels open.
- While offline, nobody defends your channels. See the watchtower note in
  `DEPLOY.md`; it matters more as balances grow and with unknown peers.
