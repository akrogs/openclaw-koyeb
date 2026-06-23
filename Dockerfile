# Imagen fijada a una version estable conocida.
# Evita ":latest": hay builds publicadas inestables (p.ej. 2026.3.2, 2026.2.26).
# Verifica/actualiza la etiqueta en:
#   https://github.com/openclaw/openclaw/pkgs/container/openclaw
FROM ghcr.io/openclaw/openclaw:2026.6.1

# Plantillas (se siembran en el volumen en el arranque via entrypoint):
#  - openclaw.json : config declarativa de los 3 agentes
#  - workspaces/   : SOUL.md + AGENTS.md (rol e instrucciones por agente)
#  - scripts de arranque y preflight
COPY openclaw.json /opt/openclaw/openclaw.json
COPY workspaces/ /opt/openclaw/workspaces/
COPY entrypoint.sh /opt/openclaw/entrypoint.sh
COPY node-start.sh /opt/openclaw/node-start.sh
COPY preflight.mjs /opt/openclaw/preflight.mjs

USER root
RUN chmod +x /opt/openclaw/entrypoint.sh /opt/openclaw/node-start.sh

# Cliente de Docker (solo el binario, estatico; el daemon es el del host via el socket
# montado en docker-compose). Lo necesita el backend de sandbox de OpenClaw, que invoca el
# comando `docker` para crear el contenedor aislado de la tool 'exec'.
COPY --from=docker:cli /usr/local/bin/docker /usr/local/bin/docker

# Python + librerias de datos para que el ORQUESTADOR genere graficas via exec (matplotlib headless,
# backend Agg) y las entregue por Telegram desde /tmp. El sandbox de tecnico no puede entregar archivos.
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-numpy python3-pandas python3-matplotlib \
    && rm -rf /var/lib/apt/lists/*
ENV MPLBACKEND=Agg

# El entrypoint corre como root para poder ajustar la propiedad del volumen
# montado por Koyeb (suele venir root-owned); luego baja a "node" para el gateway.
EXPOSE 18789
ENTRYPOINT ["/opt/openclaw/entrypoint.sh"]
