# ThunderHub for Railway
# Latest stable: https://github.com/apotdevin/thunderhub/releases
FROM apotdevin/thunderhub:0.19.0

# The account config holds the admin macaroon, so it is NOT baked into the image.
# start.sh writes it at boot from Railway env vars, into a path the non-root
# "node" user of the base image can write to.
USER root
COPY start.sh /app/thub-start.sh
RUN chmod +x /app/thub-start.sh
USER node

ENV ACCOUNT_CONFIG_PATH=/tmp/thubConfig.yaml

# Production niceties: no upstream version pings, no LN Markets promo.
ENV NO_VERSION_CHECK=true
ENV DISABLE_LNMARKETS=true

# Setting ENTRYPOINT clears the base image's CMD, so restate it.
ENTRYPOINT ["/bin/sh", "/app/thub-start.sh"]
CMD ["npm", "run", "start:prod"]
