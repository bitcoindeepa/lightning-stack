# LND (Neutrino) for Railway
# Check the latest stable tag: https://github.com/lightningnetwork/lnd/releases
FROM lightninglabs/lnd:v0.18.5-beta

# Keep config + start script OUTSIDE /data, because Railway's persistent volume
# mounts at /data and hides anything baked into that path.
COPY lnd.conf /app/lnd.conf
COPY start.sh /app/start.sh

# Use sh explicitly so we don't depend on the execute bit being set.
ENTRYPOINT ["/bin/sh", "/app/start.sh"]
