# ThunderHub for Railway
FROM apotdevin/thunderhub:latest

# Bake in the account config. It points at LND over Railway's private network
# and carries the macaroon (hex) + certificate (base64) inline, since Railway
# services cannot share files with the LND volume.
COPY thubConfig.yaml /config/thubConfig.yaml
ENV ACCOUNT_CONFIG_PATH=/config/thubConfig.yaml
