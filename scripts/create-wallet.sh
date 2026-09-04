#!/bin/sh
# Run this from YOUR OWN computer (not on Railway) during Phase 1, after LND is
# deployed and a TCP Proxy is pointed at LND's REST port 8080.
#
# Usage:
#   1) Edit PROXY below to your Railway TCP proxy host:port for port 8080.
#   2) ./create-wallet.sh genseed        -> prints your 24-word seed. WRITE IT DOWN.
#   3) Put the 24 words into SEED_WORDS below and set a password.
#   4) ./create-wallet.sh initwallet     -> creates + unlocks the wallet.

PROXY="YOUR_PROXY_HOST:PORT"          # e.g. something.proxy.rlwy.net:23456
WALLET_PASSWORD="your-strong-password"
# After genseed, paste the 24 words here as a JSON array:
SEED_WORDS='["word1","word2","word3","...","word24"]'

case "$1" in
  genseed)
    curl -k "https://$PROXY/v1/genseed"
    echo ""
    echo ">> Copy cipher_seed_mnemonic (24 words) and store them safely."
    ;;
  initwallet)
    PW_B64=$(printf '%s' "$WALLET_PASSWORD" | base64)
    curl -k -X POST "https://$PROXY/v1/initwallet" \
      -d "{\"wallet_password\": \"$PW_B64\", \"cipher_seed_mnemonic\": $SEED_WORDS}"
    echo ""
    echo ">> Wallet created + unlocked. Watch Railway logs for Neutrino sync."
    ;;
  *)
    echo "Usage: $0 genseed | initwallet"
    ;;
esac
