#!/bin/sh
# Phase 1 wallet creation. Run this from YOUR OWN computer, never on Railway.
#
# Everything is read from the environment so that no seed, password or proxy
# host is ever written into a file that git could pick up.
#
# Prerequisites:
#   - LND deployed, with ALLOW_WALLET_CREATE=1 set on the Railway service.
#   - A Railway TCP Proxy pointed at LND's REST port 8080.
#
# Usage:
#   export LND_PROXY="something.proxy.rlwy.net:23456"
#   ./create-wallet.sh genseed          # prints the 24 words - WRITE THEM DOWN
#
#   export WALLET_PASSWORD="the same value you put in Railway"
#   export SEED_WORDS='["word1","word2", ... ,"word24"]'
#   ./create-wallet.sh initwallet       # creates + unlocks the wallet
#
# -k is used on purpose: LND's self-signed cert does not cover the proxy host.

set -e

: "${LND_PROXY:?set LND_PROXY to your Railway TCP proxy host:port for port 8080}"

case "$1" in
  genseed)
    curl -k -sS "https://$LND_PROXY/v1/genseed"
    echo ""
    echo ""
    echo ">> Copy cipher_seed_mnemonic - all 24 words, in order."
    echo ">> Write them on paper. This is the ONLY backup of your funds."
    echo ">> Do not screenshot, do not put them in a password manager sync, do"
    echo ">> not paste them into a chat. Then export SEED_WORDS and run initwallet."
    ;;

  initwallet)
    : "${WALLET_PASSWORD:?set WALLET_PASSWORD - must match the Railway secret exactly}"
    : "${SEED_WORDS:?set SEED_WORDS to the 24 words as a JSON array}"

    PW_B64=$(printf '%s' "$WALLET_PASSWORD" | base64 | tr -d '\n')
    curl -k -sS -X POST "https://$LND_PROXY/v1/initwallet" \
      -H 'Content-Type: application/json' \
      -d "{\"wallet_password\":\"$PW_B64\",\"cipher_seed_mnemonic\":$SEED_WORDS}"
    echo ""
    echo ""
    echo ">> Wallet created and unlocked."
    echo ">> NOW, in Railway: delete ALLOW_WALLET_CREATE and redeploy."
    echo ">> Leaving it set keeps an unauthenticated wallet-creation RPC exposed."
    echo ">> Then watch the logs for Neutrino sync progress."
    ;;

  *)
    echo "Usage: LND_PROXY=host:port $0 genseed | initwallet"
    exit 1
    ;;
esac
