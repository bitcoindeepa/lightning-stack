# LNbits for Railway
# Latest stable: https://github.com/lnbits/lnbits/releases
#
# Configuration comes from Railway environment variables - see .env.example.
# Nothing secret lives in this image.
FROM lnbits/lnbits:v1.7.0

# LNbits needs LND's TLS cert as a FILE on disk (it is handed to httpx as a CA
# bundle path). start.sh materialises it from LND_CERT_BASE64 at boot.
COPY start.sh /app/lnbits-start.sh
RUN chmod +x /app/lnbits-start.sh

ENTRYPOINT ["/bin/sh", "/app/lnbits-start.sh"]

# Setting ENTRYPOINT clears the base image's CMD, so restate it verbatim.
CMD ["sh", "-c", "uv --offline run --no-sync lnbits --port $LNBITS_PORT --host $LNBITS_HOST --forwarded-allow-ips='*'"]
