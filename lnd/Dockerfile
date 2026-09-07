# LND (Neutrino) for Railway
# Latest stable: https://github.com/lightningnetwork/lnd/releases
FROM lightninglabs/lnd:v0.21.3-beta

# curl pushes channel.backup to Telegram and reads LND's REST event streams;
# jq turns those streams into the notification text.
USER root
RUN apk add --no-cache curl jq

# Keep config + start script OUTSIDE /data: Railway's persistent volume mounts
# at /data and hides anything baked into that path.
COPY lnd.conf /app/lnd.conf
COPY start.sh /app/start.sh

EXPOSE 9735 10009 8080

# Use sh explicitly so we don't depend on the execute bit surviving Git on Windows.
ENTRYPOINT ["/bin/sh", "/app/start.sh"]
