#!/bin/sh
set -e

# Directorio de configuracion de OpenClaw (volumen persistente en Koyeb).
CONFIG_DIR="/home/node/.openclaw"
APP_USER="node"
TPL="/opt/openclaw"
export HOME="/home/node"

# Siembra las instrucciones por agente (SOUL.md/AGENTS.md). Estos archivos son DECLARATIVOS
# (fuente de verdad = repo), asi que se SOBRESCRIBEN siempre para que los cambios lleguen a la VM.
# La memoria que el agente aprende vive en MEMORY.md/USER.md (NO estan en el repo, no se tocan aqui).
seed_workspaces() {
  for d in "$TPL"/workspaces/*/; do
    [ -d "$d" ] || continue
    id="$(basename "$d")"
    dest="$CONFIG_DIR/workspaces/$id"
    mkdir -p "$dest"
    for f in "$d"*; do
      [ -f "$f" ] || continue
      cp "$f" "$dest/$(basename "$f")"
    done
  done
}

# openclaw.json es declarativo (fuente de verdad = repo): se sobrescribe siempre.
seed_config() {
  mkdir -p "$CONFIG_DIR/workspaces"
  cp "$TPL/openclaw.json" "$CONFIG_DIR/openclaw.json"
  seed_workspaces
}

if [ "$(id -u)" = "0" ]; then
  # Fase root: asegurar propiedad del volumen montado y sembrar config/instrucciones.
  mkdir -p "$CONFIG_DIR/workspace"
  seed_config
  chown -R "$APP_USER":"$APP_USER" "$CONFIG_DIR" 2>/dev/null || true

  # Bajar a "node" para arrancar el gateway (cadena de fallback segun lo disponible).
  if command -v gosu >/dev/null 2>&1; then
    exec gosu "$APP_USER" "$TPL/node-start.sh"
  elif command -v su-exec >/dev/null 2>&1; then
    exec su-exec "$APP_USER" "$TPL/node-start.sh"
  elif command -v su >/dev/null 2>&1; then
    exec su -s /bin/sh "$APP_USER" -c "$TPL/node-start.sh"
  else
    echo "[entrypoint] aviso: no se pudo cambiar a '$APP_USER'; ejecutando como root." >&2
    exec "$TPL/node-start.sh"
  fi
else
  # Ya somos usuario sin privilegios: sembrar lo posible y arrancar.
  seed_config
  exec "$TPL/node-start.sh"
fi
