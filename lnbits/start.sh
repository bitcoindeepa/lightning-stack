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

# Wait for Postgres to actually accept connections before starting LNbits.
#
# LNbits does not retry its startup DB connection - one failed attempt is
# fatal, and it exits. If Postgres restarts at the same time as this
# container (Railway does this together sometimes), LNbits can lose the race
# against Postgres's own boot time, burn through Railway's restart budget in
# seconds (it exits near-instantly, no backoff), and then just stay dead.
#
# LNBITS_DATABASE_URL is postgres://user:pass@host:port/db - pull host/port
# out of it with Python, since it's always present in this image and shell
# URL-parsing is fragile.
if [ -n "$LNBITS_DATABASE_URL" ]; then
  HOST_PORT=$(python3 -c "
import sys
from urllib.parse import urlparse
u = urlparse('$LNBITS_DATABASE_URL'.replace('postgres://', 'postgresql://', 1))
print(f'{u.hostname} {u.port or 5432}')
")
  DB_HOST=$(echo "$HOST_PORT" | cut -d' ' -f1)
  DB_PORT=$(echo "$HOST_PORT" | cut -d' ' -f2)

  echo "[start.sh] waiting for Postgres at $DB_HOST:$DB_PORT..."
  i=0
  until python3 -c "
import socket
s = socket.create_connection(('$DB_HOST', $DB_PORT), timeout=2)
s.close()
" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 30 ]; then
      echo "[start.sh] FATAL: Postgres at $DB_HOST:$DB_PORT not reachable after 60s." >&2
      exit 1
    fi
    sleep 2
  done
  echo "[start.sh] Postgres is reachable, starting LNbits"
fi

exec "$@"
