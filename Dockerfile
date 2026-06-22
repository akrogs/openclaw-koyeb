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

# --- Deno + Pyodide (WASM) para ejecutar Python AISLADO via mcp-run-python (transporte stdio) ---
# El binario de Deno se copia desde la imagen oficial (sin curl). La cache de Pyodide se
# pre-calienta en build (modo "warmup") para que la 1a ejecucion en runtime sea instantanea
# y sin descargas. DENO_DIR y el cwd se hornean en la imagen y se ceden al usuario "node".
COPY --from=denoland/deno:bin /deno /usr/local/bin/deno
ENV DENO_DIR=/opt/deno-cache
RUN mkdir -p /opt/deno-cache /opt/mcp-python \
 && cd /opt/mcp-python \
 && deno run -N -R=node_modules -W=node_modules --node-modules-dir=auto jsr:@pydantic/mcp-run-python warmup \
 && chown -R node:node /opt/deno-cache /opt/mcp-python

# El entrypoint corre como root para poder ajustar la propiedad del volumen
# montado por Koyeb (suele venir root-owned); luego baja a "node" para el gateway.
EXPOSE 18789
ENTRYPOINT ["/opt/openclaw/entrypoint.sh"]
