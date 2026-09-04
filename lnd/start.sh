#!/bin/sh
# Entrypoint for LND on Railway.
# - Writes the wallet-unlock password file (for auto-unlock) if WALLET_PASSWORD is set.
# - Optionally dumps TLS cert + admin macaroon as hex AND base64 to the logs,
#   so you can wire up ThunderHub and LNbits (Railway services can't share files).

set -e

# 1) Auto-unlock: write the password file from a Railway secret (never commit it).
if [ -n "$WALLET_PASSWORD" ]; then
  printf '%s' "$WALLET_PASSWORD" > /data/walletpassword.txt
  echo "[start.sh] wrote /data/walletpassword.txt for auto-unlock"
fi

# 2) Credential dump: set PRINT_CREDS=1 in Railway, redeploy, copy from logs,
#    then REMOVE the variable. Only works after the wallet has been created.
if [ "$PRINT_CREDS" = "1" ]; then
  CERT=/data/tls.cert
  MAC=/data/data/chain/bitcoin/mainnet/admin.macaroon

  to_hex() {
    # Try several tools; one of them should exist in the image.
    hexdump -ve '1/1 "%.2x"' "$1" 2>/dev/null \
      || xxd -ps -c 100000 "$1" 2>/dev/null | tr -d '\n' \
      || od -An -tx1 "$1" 2>/dev/null | tr -d ' \n'
  }

  echo "========== TLS CERT (hex) =========="
  to_hex "$CERT" || echo "(tls.cert not found yet)"
  echo ""
  echo "========== TLS CERT (base64) =========="
  base64 "$CERT" 2>/dev/null | tr -d '\n' || echo "(base64 unavailable)"
  echo ""
  echo "========== ADMIN MACAROON (hex) =========="
  to_hex "$MAC" || echo "(admin.macaroon not found yet)"
  echo ""
  echo "========== ADMIN MACAROON (base64) =========="
  base64 "$MAC" 2>/dev/null | tr -d '\n' || echo "(base64 unavailable)"
  echo ""
  echo "========== END CREDS =========="
fi

# 3) Start LND. Data (wallet, channels, neutrino, tls, macaroons) lives on /data.
exec lnd --lnddir=/data --configfile=/app/lnd.conf
