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
  # Semilla del package.json de trading (deps como tweetnacl): SOLO si no existe ya en el volumen.
  # El del volumen MANDA (patron "seed-if-missing", igual que SOUL.md/AGENTS.md); el del repo solo
  # cubre un volumen nuevo/reseteado. node-start.sh hace el npm install si falta tweetnacl.
  if [ -f "$TPL/workspaces/orquestador/trading/package.json" ] \
     && [ ! -f "$CONFIG_DIR/workspaces/orquestador/trading/package.json" ]; then
    mkdir -p "$CONFIG_DIR/workspaces/orquestador/trading"
    cp "$TPL/workspaces/orquestador/trading/package.json" "$CONFIG_DIR/workspaces/orquestador/trading/package.json"
  fi
}

if [ "$(id -u)" = "0" ]; then
  # Fase root: asegurar propiedad del volumen montado y sembrar config/instrucciones.
  mkdir -p "$CONFIG_DIR/workspace"
  seed_config
  chown -R "$APP_USER":"$APP_USER" "$CONFIG_DIR" 2>/dev/null || true

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

  # Auto-start del clay-sandbox (market data OKX en 127.0.0.1:9000) si el binario existe en el
  # workspace. El proceso muere al reiniciar el contenedor, por eso se re-lanza en cada arranque.
  # Corre como "$APP_USER" desde su directorio (lee .env.clay). Solo se re-lanza si el binario esta.
  CLAY_DIR="$CONFIG_DIR/workspaces/orquestador/skills/claw-wallet"
  if [ -x "$CLAY_DIR/clay-sandbox" ]; then
    CLAY_ADDR="127.0.0.1:9000"
    if [ -f "$CLAY_DIR/.env.clay" ]; then
      _a="$(grep -E '^LISTEN_ADDR=' "$CLAY_DIR/.env.clay" | head -1 | cut -d= -f2- | tr -d '\r')"
      [ -n "$_a" ] && CLAY_ADDR="$_a"
    fi
    if command -v gosu >/dev/null 2>&1; then
      gosu "$APP_USER" sh -c "cd '$CLAY_DIR' && nohup ./clay-sandbox > sandbox.log 2>&1 &"
    else
      ( cd "$CLAY_DIR" && nohup ./clay-sandbox > sandbox.log 2>&1 & )
    fi
    echo "[entrypoint] clay-sandbox started on $CLAY_ADDR"
  else
    echo "[entrypoint] clay-sandbox not found, skipping"
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
