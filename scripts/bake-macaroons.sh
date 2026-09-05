#!/bin/sh
# Bake scoped macaroons so no service holds admin rights it does not need.
#
# RUN THIS IN THE LND CONTAINER'S CONSOLE (Railway -> lnd -> Console), not on
# your laptop. It needs lncli and the admin macaroon that lives on the volume.
#
# Why bother: the admin macaroon can open and close channels and move on-chain
# funds. LNbits is the most exposed service in this stack (public domain, public
# registration, largest attack surface) and needs none of that. If it is ever
# compromised, a scoped macaroon means the attacker cannot drain the on-chain
# wallet or force-close channels.
#
# Permissions reference: lncli bakemacaroon --help

set -e

OUT=/data/baked
mkdir -p "$OUT"

# --- LNbits ----------------------------------------------------------------
# Derived from the only endpoints lnbits/wallets/lndrest.py calls:
#   /v1/balance/channels          -> offchain:read
#   /v1/invoices, /v1/invoice/*   -> invoices:read + invoices:write
#   /v2/invoices/{hodl,settle,cancel}
#   /v2/router/send, /v2/router/track -> offchain:write + offchain:read
#
# Deliberately absent: onchain:write (cannot spend the wallet), address:write,
# peers:write, macaroon:generate, and anything that can close a channel.
lncli bakemacaroon \
  --save_to="$OUT/lnbits.macaroon" \
  invoices:read invoices:write \
  offchain:read offchain:write

echo ""
echo "===== LNbits macaroon (hex) -> LND_REST_MACAROON ====="
hexdump -ve '1/1 "%.2x"' "$OUT/lnbits.macaroon"
echo ""

# --- ThunderHub ------------------------------------------------------------
# ThunderHub manages channels, so it needs materially more. This still drops
# macaroon:generate (it cannot mint further macaroons) and onchain:write (it
# cannot send your on-chain funds anywhere).
#
# If you DO want to send on-chain from ThunderHub, add onchain:write - but then
# it is close enough to admin that the distinction stops meaning much.
lncli bakemacaroon \
  --save_to="$OUT/thunderhub.macaroon" \
  info:read \
  onchain:read \
  offchain:read offchain:write \
  invoices:read invoices:write \
  address:read address:write \
  peers:read peers:write \
  signer:read

echo ""
echo "===== ThunderHub macaroon (hex) -> LND_MACAROON_HEX ====="
hexdump -ve '1/1 "%.2x"' "$OUT/thunderhub.macaroon"
echo ""

echo "Now update both Railway services, redeploy, and confirm each still works."
echo "Then treat the ADMIN macaroon as console-only - no service should hold it."
