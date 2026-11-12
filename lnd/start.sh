#!/bin/sh
# Entrypoint for LND on Railway.
#
#   1) Writes the wallet-unlock password file from the WALLET_PASSWORD secret.
#   2) Watches channel.backup (SCB) and pushes it to Telegram whenever it changes.
#   3) Streams LND's own payment/channel events to Telegram as notifications.
#   4) Optionally dumps TLS cert + admin macaroon to the logs, so ThunderHub and
#      LNbits can be wired up (Railway services cannot share files).
#   5) Starts LND.
#
# Env vars (set in Railway, never in this repo):
#   WALLET_PASSWORD       required. Unlocks the wallet on every restart.
#   ALLOW_WALLET_CREATE   Phase 1 only. "1" lets you create the wallet over REST.
#   REGEN_TLS             "1" deletes tls.cert/tls.key on boot so LND reissues
#                         them. Needed after changing tlsextradomain. Remove it
#                         again straight after, and re-dump PRINT_CREDS.
#   LND_EXTERNAL_ADDR     "host:port" of the Railway TCP proxy for port 9735.
#   TELEGRAM_BOT_TOKEN    channel backup + notification destination.
#   TELEGRAM_CHAT_ID      channel backup + notification destination. For a group
#                         this is NEGATIVE and supergroups carry a -100 prefix,
#                         e.g. t.me/c/2611800824/... -> -1002611800824.
#   TELEGRAM_THREAD_ID    optional. Topic id in a forum group - the second
#                         number in a t.me/c/<chat>/<topic> link. Unset posts to
#                         the group's General topic.
#   TELEGRAM_NOTIFY       "0" disables the payment/channel notifications only.
#                         The channel.backup push is NOT optional and ignores it.
#   PRINT_CREDS           "1" dumps credentials to the logs once, then remove it.

set -e

LNDDIR=/data
CHAINDIR="$LNDDIR/data/chain/bitcoin/mainnet"
SCB="$CHAINDIR/channel.backup"
# LND's own REST listener. rpclisten/restlisten bind [::], so loopback is [::1].
REST="https://[::1]:8080"

# Telegram forum groups (groups with Topics on) address a topic with
# message_thread_id. Without it, messages land in "General" rather than the
# thread. The parameter must be OMITTED when unused - Telegram rejects an empty
# value rather than ignoring it, so this builds the argument or an empty string.
# Unquoted expansion below is deliberate and safe: the id is always numeric.
TG_DOC_THREAD=""
TG_MSG_THREAD=""
if [ -n "$TELEGRAM_THREAD_ID" ]; then
  TG_DOC_THREAD="-F message_thread_id=$TELEGRAM_THREAD_ID"
  TG_MSG_THREAD="--data message_thread_id=$TELEGRAM_THREAD_ID"
fi

to_hex() {
  hexdump -ve '1/1 "%.2x"' "$1" 2>/dev/null \
    || xxd -ps -c 100000 "$1" 2>/dev/null | tr -d '\n' \
    || od -An -tx1 "$1" 2>/dev/null | tr -d ' \n'
}

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
    -F "chat_id=$TELEGRAM_CHAT_ID" $TG_DOC_THREAD \
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

# --- 2b) Payment + channel notifier ---------------------------------------
# ThunderHub has its own Telegram bot, but it is driven by the `lightning` npm
# library's gRPC subscriptions, which die against this LND version with
# ExpectedEventTypeInChannelSubscription ("Initiating subscriptions failed" in
# the ThunderHub logs). So we read LND's REST event streams here instead:
# same container, no cert/macaroon plumbing, no version skew.
tg_notify() {
  curl -s -o /dev/null -w '[start.sh] telegram notify HTTP %{http_code}\n' \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" $TG_MSG_THREAD \
    --data-urlencode "text=$1" \
    --data "disable_web_page_preview=true" \
    "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    || echo "[start.sh] telegram notify failed"
}

# The REST gateway marshals every protobuf `bytes` field as base64, so an
# invoice's r_hash arrives base64-encoded - while LNbits, ThunderHub, explorers
# and lncli all identify a payment by that hash in HEX. jq cannot do the
# conversion (decoded hashes are not valid UTF-8, so @base64d corrupts them),
# so filters emit a {{b64hex:<value>}} token and this expands it.
#
# routerrpc's payment_hash is a plain string field and already hex, so only the
# invoice filter needs this.
expand_b64hex() {
  out="$1"
  while true; do
    tok=$(printf '%s' "$out" | sed -n 's/.*{{b64hex:\([^}]*\)}}.*/\1/p' | head -n 1)
    if [ -z "$tok" ]; then break; fi
    hex=$(printf '%s' "$tok" | base64 -d 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
    # A token that will not decode is replaced by a marker rather than left in
    # place, which would spin this loop forever.
    if [ -z "$hex" ]; then hex="(undecodable)"; fi
    out=$(printf '%s' "$out" | sed "s|{{b64hex:$tok}}|$hex|g")
  done
  printf '%s' "$out"
}

# LND's streaming REST endpoints emit one {"result": ...} JSON object per line
# and hold the connection open. curl exits whenever LND restarts, is still
# locked, or the stream breaks, so each watcher reconnects on a loop.
#
# --insecure is safe and necessary here: this is a loopback connection inside
# LND's own container, and tlsdisableautofill means the cert's SANs cover the
# Railway domains rather than [::1].
#
# readonly.macaroon, not admin: these streams only need read permissions, and
# a compromised notifier should not be able to move funds. It does not exist
# until the wallet does, which is what the emptiness check below waits for.
stream_watch() {
  name="$1"; path="$2"; filter="$3"
  while true; do
    mac=$(to_hex "$CHAINDIR/readonly.macaroon" 2>/dev/null || true)
    if [ -n "$mac" ]; then
      curl -s --no-buffer --insecure \
        -H "Grpc-Metadata-macaroon: $mac" \
        "$REST$path" 2>/dev/null \
      | while IFS= read -r line; do
          msg=$(printf '%s' "$line" | jq -r "$filter" 2>/dev/null || true)
          case "$msg" in *'{{b64hex:'*) msg=$(expand_b64hex "$msg") ;; esac
          if [ -n "$msg" ] && [ "$msg" != "null" ]; then
            echo "[start.sh] notify ($name): $(printf '%s' "$msg" | head -n 1)"
            tg_notify "$msg"
          fi
        done
    fi
    sleep 10
  done
}

# Invoices. SubscribeInvoices with no add_index/settle_index starts from "now",
# so a redeploy does not replay old payments. Every invoice hits this twice
# (OPEN on creation, SETTLED on payment); only the settle is worth a message.
watch_invoices() {
  stream_watch invoice /v1/invoices/subscribe '
    select(.result.state == "SETTLED")
    | "⚡ Received \(.result.amt_paid_sat) sats"
      + (if (.result.memo // "") == "" then "" else "\n\(.result.memo)" end)
      + (if (.result.r_hash // "") == "" then ""
         else "\nid: {{b64hex:\(.result.r_hash)}}" end)
  '
}

# Sends. This is router.TrackPayments, which covers everything leaving the node
# - ThunderHub, LNbits, and LNbits sub-wallets alike. no_inflight_updates keeps
# it to one message per payment instead of one per routing attempt.
watch_payments() {
  stream_watch payment '/v2/router/payments?no_inflight_updates=true' '
    if .result.status == "SUCCEEDED" then
      "✅ Sent \(.result.value_sat) sats (fee \(.result.fee_sat))"
    elif .result.status == "FAILED" then
      "❌ Send failed: \(.result.value_sat) sats (\(.result.failure_reason))"
    else empty end
  '
}

# Channels. Only opens and closes - active/inactive fire on every peer
# reconnect and would drown the chat.
watch_channels() {
  stream_watch channel /v1/channels/subscribe '
    if .result.open_channel then
      "🔗 Channel OPENED with \(.result.open_channel.remote_pubkey[0:16])…"
      + "\ncapacity \(.result.open_channel.capacity) sats"
      + ", local \(.result.open_channel.local_balance) sats"
    elif .result.closed_channel then
      "🔒 Channel CLOSED with \(.result.closed_channel.remote_pubkey[0:16])…"
      + "\n\(.result.closed_channel.close_type), settled \(.result.closed_channel.settled_balance) sats"
    else empty end
  '
}

if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ] \
   && [ "$TELEGRAM_NOTIFY" != "0" ] && command -v jq >/dev/null 2>&1; then
  watch_invoices &
  watch_payments &
  watch_channels &
  echo "[start.sh] Telegram notifier started (invoices, payments, channels)"
  # Doubles as a restart alert and as proof the wiring still works after a
  # redeploy - the watchers are otherwise silent until something is paid.
  tg_notify "🟠 BitcoinDeepa node starting - $(date -u '+%Y-%m-%d %H:%M UTC')" &
elif [ "$TELEGRAM_NOTIFY" = "0" ]; then
  echo "[start.sh] TELEGRAM_NOTIFY=0, payment notifications disabled"
fi

# --- 3) Credential dump ----------------------------------------------------
# Set PRINT_CREDS=1 in Railway, redeploy, copy from the logs, then REMOVE the
# variable and redeploy again. Only works once the wallet exists.
if [ "$PRINT_CREDS" = "1" ]; then
  CERT="$LNDDIR/tls.cert"
  MAC="$CHAINDIR/admin.macaroon"

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
