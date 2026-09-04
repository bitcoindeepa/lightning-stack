#!/bin/sh
# Writes LND's TLS cert to a file before starting LNbits.
#
# LNbits passes LND_REST_CERT straight to httpx's verify= argument:
#
#     cert = settings.lnd_rest_cert or True
#     httpx.AsyncClient(..., verify=cert)
#
# httpx accepts a bool, an ssl.SSLContext, or a PATH to a CA bundle - it does
# NOT accept cert contents. Passing hex or base64 fails with
# "[Errno 36] File name too long" and LNbits falls back to VoidWallet.
#
# Railway services cannot share files with LND's volume, so take the cert as an
# env var and materialise it here.
#
# Env vars (set in Railway):
#   LND_CERT_BASE64   TLS CERT (base64) from the LND credential dump.

set -e

CERT_PATH=/app/lnd-tls.cert

if [ -n "$LND_CERT_BASE64" ]; then
  printf '%s' "$LND_CERT_BASE64" | base64 -d > "$CERT_PATH"
  # Sanity check: a PEM cert must start with the BEGIN line. Catches a value
  # that was pasted as hex, truncated, or line-wrapped by the shell.
  if ! head -1 "$CERT_PATH" | grep -q "BEGIN CERTIFICATE"; then
    echo "[start.sh] FATAL: LND_CERT_BASE64 did not decode to a PEM certificate." >&2
    echo "[start.sh] Expected base64 of tls.cert - not hex, and not the macaroon." >&2
    exit 1
  fi
  export LND_REST_CERT="$CERT_PATH"
  echo "[start.sh] wrote $CERT_PATH and set LND_REST_CERT to it"
else
  echo "[start.sh] WARNING: LND_CERT_BASE64 not set."
  echo "[start.sh] LNbits will verify against public CAs and reject LND's"
  echo "[start.sh] self-signed cert, then fall back to VoidWallet."
fi

exec "$@"
