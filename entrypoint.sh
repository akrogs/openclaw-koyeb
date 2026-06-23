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

  # Dir de salida compartido del sandbox (paridad de rutas): el sandbox de exec escribe aqui
  # (p.ej. graficas) y el gateway lo lee para entregarlo. Scratch -> permisos abiertos.
  mkdir -p /srv/out && chmod 777 /srv/out 2>/dev/null || true

  # DooD: si el socket de Docker esta montado (para el sandbox de la tool 'exec'), dar acceso
  # al usuario "node" anadiendolo al grupo del socket. El GID del socket varia por host, asi
  # que lo detectamos en runtime y creamos el grupo si hace falta (arregla el clasico
  # "docker.sock permission denied"). Si falla, solo el sandbox de exec se vera afectado.
  if [ -S /var/run/docker.sock ]; then
    DGID="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || true)"
    if [ -n "$DGID" ]; then
      GRP="$(getent group "$DGID" | cut -d: -f1)"
      if [ -z "$GRP" ]; then
        groupadd -g "$DGID" dockerhost 2>/dev/null && GRP=dockerhost
      fi
      if [ -n "$GRP" ] && usermod -aG "$GRP" "$APP_USER" 2>/dev/null; then
        echo "[entrypoint] '$APP_USER' con acceso al docker.sock (grupo '$GRP', gid $DGID)."
      else
        echo "[entrypoint] aviso: no pude dar acceso al docker.sock a '$APP_USER'; el sandbox de exec podria fallar." >&2
      fi
    fi
  fi

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
