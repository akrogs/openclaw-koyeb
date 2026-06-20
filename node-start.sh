#!/bin/sh
set -e

export HOME="/home/node"
TPL="/opt/openclaw"
CONFIG="$HOME/.openclaw/openclaw.json"

# Registra el perfil de auth de OpenRouter desde la env inyectada por Koyeb.
# Idempotente; se guarda en el volumen y mantiene la clave FUERA del config versionado.
# (Confirma el subcomando/flags reales con `openclaw auth --help`.)
if [ -n "$OPENROUTER_API_KEY" ]; then
  openclaw auth set openrouter:default --key "$OPENROUTER_API_KEY" \
    || echo "[node-start] aviso: 'openclaw auth set' fallo; revisa el comando/flags reales." >&2
else
  echo "[node-start] aviso: OPENROUTER_API_KEY no definido; los modelos no autenticaran." >&2
fi

# Preflight de modelos: aborta el arranque si algun slug :free configurado no existe
# en OpenRouter. Tolera fallos de red (no bloquea). Desactivable con SKIP_MODEL_PREFLIGHT=1.
if [ "${SKIP_MODEL_PREFLIGHT:-0}" != "1" ]; then
  node "$TPL/preflight.mjs" "$CONFIG"
fi

# Arranca el gateway. NOTA: confirma el comando real con
#   docker inspect ghcr.io/openclaw/openclaw:2026.6.1
exec openclaw gateway
