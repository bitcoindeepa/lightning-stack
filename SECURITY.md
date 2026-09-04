# SECURITY.md - Exposure and lock-down

Your node holds real funds and is always online. Treat access carefully.

## What should face the public internet
- **Port 9735 (Lightning p2p) only.** This is meant to be reachable (via Railway TCP
  proxy) so peers can connect and open inbound channels.

## What should NOT be publicly exposed without protection
- **gRPC (10009) and REST (8080).** Only expose when an external app needs them.
  During Phase 1 we temporarily TCP-proxy 8080 to create the wallet - REMOVE that
  proxy afterward if you don't need external REST.
- **ThunderHub (3000) and LNbits ($PORT).** These get public Railway domains so you
  can reach them, but:
  - ThunderHub is protected by its `masterPassword` - set a strong one.
  - LNbits wallets are protected by their per-wallet keys/URLs - treat wallet admin
    keys like passwords; consider enabling LNbits auth features.

## Credential hygiene
- `PRINT_CREDS=1` dumps the macaroon/cert to logs. Use it briefly, then remove the
  variable so creds stop printing. Anyone with log access could read them.
- Never commit `.env`, `walletpassword.txt`, the seed, or any `*.macaroon` /
  `tls.*`. See `.gitignore`.
- Rotate/rebake macaroons if you ever suspect exposure. If you change
  `tlsextradomain`, delete `tls.cert` + `tls.key` so LND regenerates them (then
  re-dump creds for ThunderHub/LNbits).

## Backups
- 24-word seed offline (metal backup ideal).
- Export the Static Channel Backup (channel.backup) from ThunderHub and keep it safe.
