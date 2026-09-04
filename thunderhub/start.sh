#!/bin/sh
# Generates thubConfig.yaml at boot from Railway environment variables.
#
# The config carries the admin macaroon, so it must NEVER be a committed file.
# Building it here keeps the secret in Railway's variable store only.
#
# Env vars (set in Railway):
#   THUB_MASTER_PASSWORD  login password for the ThunderHub UI
#   LND_MACAROON_HEX      ADMIN MACAROON (hex) from the LND credential dump
#   LND_CERT_BASE64       TLS CERT (base64) from the LND credential dump
#   LND_GRPC_HOST         defaults to lnd.railway.internal:10009
#   THUB_ACCOUNT_NAME     defaults to BitcoinDeepa

set -e

CONFIG="${ACCOUNT_CONFIG_PATH:-/tmp/thubConfig.yaml}"

for v in THUB_MASTER_PASSWORD LND_MACAROON_HEX LND_CERT_BASE64; do
  eval "val=\$$v"
  if [ -z "$val" ]; then
    echo "[start.sh] FATAL: $v is not set. Set it in Railway and redeploy." >&2
    exit 1
  fi
done

# Single-quoted YAML scalars: safe because these values are hex/base64/generated
# passwords. If you ever set a password containing a single quote, double it.
cat > "$CONFIG" <<EOF
masterPassword: '$THUB_MASTER_PASSWORD'

accounts:
  - name: '${THUB_ACCOUNT_NAME:-BitcoinDeepa}'
    serverUrl: '${LND_GRPC_HOST:-lnd.railway.internal:10009}'
    macaroon: '$LND_MACAROON_HEX'
    certificate: '$LND_CERT_BASE64'
EOF

echo "[start.sh] wrote $CONFIG for account ${THUB_ACCOUNT_NAME:-BitcoinDeepa}"

exec "$@"
