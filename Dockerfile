FROM ghcr.io/openclaw/openclaw:latest

# Plantilla de configuracion declarativa de los 3 agentes.
# Se copia al directorio de config (volumen persistente) en el arranque via entrypoint,
# para no chocar con el montaje del volumen en /home/node/.openclaw.
COPY openclaw.json /opt/openclaw/openclaw.json
COPY entrypoint.sh /opt/openclaw/entrypoint.sh

USER root
RUN chmod +x /opt/openclaw/entrypoint.sh
USER node

# Puerto del Gateway Control UI / API.
EXPOSE 18789

ENTRYPOINT ["/opt/openclaw/entrypoint.sh"]
