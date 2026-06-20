#!/bin/sh
set -e

export HOME="/home/node"
TPL="/opt/openclaw"
CONFIG="$HOME/.openclaw/openclaw.json"

# Auth de proveedores por variable de entorno (inyectadas por Koyeb):
#   - GEMINI_API_KEY            -> proveedor nativo "google"
#   - GROQ_API_KEY/CEREBRAS_API_KEY -> referenciadas en models.providers (${...}) del openclaw.json
# No hace falta 'openclaw auth set'. Avisa si falta alguna clave.
[ -n "$GEMINI_API_KEY" ]   || echo "[node-start] aviso: GEMINI_API_KEY no definido; 'google' no autenticara." >&2
[ -n "$GROQ_API_KEY" ]     || echo "[node-start] aviso: GROQ_API_KEY no definido; 'groq' no autenticara." >&2
[ -n "$CEREBRAS_API_KEY" ] || echo "[node-start] aviso: CEREBRAS_API_KEY no definido; 'cerebras' no autenticara." >&2

# Preflight multi-proveedor: verifica que los IDs configurados existen en cada proveedor (con su clave).
# Aborta solo ante un ID invalido; tolera fallos de red. Desactivable con SKIP_MODEL_PREFLIGHT=1.
if [ "${SKIP_MODEL_PREFLIGHT:-0}" != "1" ]; then
  node "$TPL/preflight.mjs" "$CONFIG"
fi

# Arranca el gateway. NOTA: confirma el comando real con
#   docker inspect ghcr.io/openclaw/openclaw:2026.6.1
exec openclaw gateway
