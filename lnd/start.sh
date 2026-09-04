#!/bin/sh
# Entrypoint for LND on Railway.
#
#   1) Writes the wallet-unlock password file from the WALLET_PASSWORD secret.
#   2) Watches channel.backup (SCB) and pushes it to Telegram whenever it changes.
#   3) Optionally dumps TLS cert + admin macaroon to the logs, so ThunderHub and
#      LNbits can be wired up (Railway services cannot share files).
#   4) Starts LND.
#
# Env vars (set in Railway, never in this repo):
#   WALLET_PASSWORD       required. Unlocks the wallet on every restart.
#   ALLOW_WALLET_CREATE   Phase 1 only. "1" lets you create the wallet over REST.
#   REGEN_TLS             "1" deletes tls.cert/tls.key on boot so LND reissues
#                         them. Needed after changing tlsextradomain. Remove it
#                         again straight after, and re-dump PRINT_CREDS.
#   LND_EXTERNAL_ADDR     "host:port" of the Railway TCP proxy for port 9735.
#   TELEGRAM_BOT_TOKEN    channel backup destination.
#   TELEGRAM_CHAT_ID      channel backup destination.
#   PRINT_CREDS           "1" dumps credentials to the logs once, then remove it.

set -e

LNDDIR=/data
CHAINDIR="$LNDDIR/data/chain/bitcoin/mainnet"
SCB="$CHAINDIR/channel.backup"

# --- 1) Auto-unlock --------------------------------------------------------
if [ -n "$WALLET_PASSWORD" ]; then
  printf '%s' "$WALLET_PASSWORD" > "$LNDDIR/walletpassword.txt"
  chmod 600 "$LNDDIR/walletpassword.txt"
  echo "[start.sh] wrote walletpassword.txt for auto-unlock"
else
  echo "[start.sh] WARNING: WALLET_PASSWORD is not set. LND will not auto-unlock."
fi

# --- 1b) One-shot TLS regeneration ----------------------------------------
# tlsautorefresh is off, so LND reuses whatever tls.cert is already on the
# volume and IGNORES changes to tlsextradomain. Set REGEN_TLS=1 to delete the
# cert and key so LND issues a fresh pair covering the current domain list.
#
# This does NOT touch the wallet, channels or macaroons - only the TLS pair.
# But it DOES invalidate the cert hex/base64 held by ThunderHub and LNbits, so
# afterwards re-run with PRINT_CREDS=1 and update both services.
#
# Remove the variable once done, or every restart issues a new cert and both
# services break again.
if [ "$REGEN_TLS" = "1" ]; then
  echo "[start.sh] REGEN_TLS=1 - deleting tls.cert/tls.key so LND reissues them"
  rm -f "$LNDDIR/tls.cert" "$LNDDIR/tls.key"
  echo "[start.sh] !! ThunderHub and LNbits now hold a STALE cert."
  echo "[start.sh] !! Redeploy with PRINT_CREDS=1 and update both, then REMOVE REGEN_TLS."
fi

# --- 2) Channel backup watcher --------------------------------------------
# channel.backup is the ONLY way to recover channel funds if this volume dies.
# LND rewrites it on every channel open/close, so we ship each new version out.
tg_send_backup() {
  reason="$1"
  curl -s -o /dev/null -w '[start.sh] telegram HTTP %{http_code}\n' \
    -F "chat_id=$TELEGRAM_CHAT_ID" \
    -F "caption=BitcoinDeepa LND channel.backup ($reason) - $(date -u '+%Y-%m-%d %H:%M UTC')" \
    -F "document=@$SCB;filename=channel.backup" \
    "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument" \
    || echo "[start.sh] telegram push failed"
}

watch_scb() {
  last=""
  while true; do
    if [ -f "$SCB" ]; then
      now=$(sha256sum "$SCB" | cut -d' ' -f1)
      if [ "$now" != "$last" ]; then
        if [ -z "$last" ]; then reason="startup"; else reason="channel change"; fi
        echo "[start.sh] channel.backup changed ($reason), pushing to Telegram"
        tg_send_backup "$reason"
        last="$now"
      fi
    fi
    sleep 30
  done
}

if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
  if command -v curl >/dev/null 2>&1; then
    watch_scb &
    echo "[start.sh] channel.backup watcher started (Telegram)"
  else
    echo "[start.sh] WARNING: curl missing, channel backups will NOT be pushed"
  fi
else
  echo "[start.sh] WARNING: TELEGRAM_* not set, channel backups will NOT be pushed"
fi

# --- 3) Credential dump ----------------------------------------------------
# Set PRINT_CREDS=1 in Railway, redeploy, copy from the logs, then REMOVE the
# variable and redeploy again. Only works once the wallet exists.
if [ "$PRINT_CREDS" = "1" ]; then
  CERT="$LNDDIR/tls.cert"
  MAC="$CHAINDIR/admin.macaroon"

  to_hex() {
    hexdump -ve '1/1 "%.2x"' "$1" 2>/dev/null \
      || xxd -ps -c 100000 "$1" 2>/dev/null | tr -d '\n' \
      || od -An -tx1 "$1" 2>/dev/null | tr -d ' \n'
  }

  echo "========== TLS CERT (hex)  -> LNbits LND_REST_CERT =========="
  to_hex "$CERT" || echo "(tls.cert not found yet)"
  echo ""
  echo "========== TLS CERT (base64) -> ThunderHub LND_CERT_BASE64 =========="
  base64 "$CERT" 2>/dev/null | tr -d '\n' || echo "(base64 unavailable)"
  echo ""
  echo "========== ADMIN MACAROON (hex) -> both LNbits + ThunderHub =========="
  to_hex "$MAC" || echo "(admin.macaroon not found yet)"
  echo ""
  echo "========== END CREDS - now REMOVE PRINT_CREDS =========="
fi

# --- 4) Start LND ----------------------------------------------------------
set -- lnd --lnddir="$LNDDIR" --configfile=/app/lnd.conf

# Advertise the Railway TCP proxy so other nodes can open channels TO us.
# The proxy port differs from 9735, so this must be host:port, not just a host.
if [ -n "$LND_EXTERNAL_ADDR" ]; then
  echo "[start.sh] advertising external address $LND_EXTERNAL_ADDR"
  set -- "$@" --externalip="$LND_EXTERNAL_ADDR"
fi

# Phase 1 only: lets LND boot with the password file set but no wallet yet, so
# the wallet can be created over REST. The creation RPC is UNAUTHENTICATED while
# this is on - remove the variable as soon as the wallet exists.
if [ "$ALLOW_WALLET_CREATE" = "1" ]; then
  echo "[start.sh] !! ALLOW_WALLET_CREATE=1 - wallet creation RPC is OPEN. Phase 1 only."
  set -- "$@" --wallet-unlock-allow-create
fi

exec "$@"
