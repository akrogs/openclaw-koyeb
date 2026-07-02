#!/bin/sh
set -e

export HOME="/home/node"
TPL="/opt/openclaw"
CONFIG="$HOME/.openclaw/openclaw.json"

# Auth de proveedores por variables del .env (referenciadas con ${...} en openclaw.json, o leidas por
# el proveedor built-in en zai/openrouter). No hace falta 'openclaw auth set'. Avisa si falta alguna
# clave que SI se usa hoy (Gemini/Groq quedaron fuera).
[ -n "$ZAI_API_KEY" ]        || echo "[node-start] aviso: ZAI_API_KEY no definido; 'zai' (PRIMARIO de orquestador/tecnico) no autenticara." >&2
[ -n "$NVIDIA_API_KEY" ]     || echo "[node-start] aviso: NVIDIA_API_KEY no definido; 'nvidia' (Kimi/vision + fallbacks) no autenticara." >&2
[ -n "$ZENMUX_API_KEY" ]     || echo "[node-start] aviso: ZENMUX_API_KEY no definido; 'zenmux' (fallback GLM 5.2 free) no autenticara." >&2
[ -n "$CEREBRAS_API_KEY" ]   || echo "[node-start] aviso: CEREBRAS_API_KEY no definido; 'cerebras' (formato) no autenticara." >&2
[ -n "$OPENROUTER_API_KEY" ] || echo "[node-start] aviso: OPENROUTER_API_KEY no definido; ultimo fallback de chat no autenticara." >&2

# Preflight multi-proveedor: verifica que los IDs configurados existen en cada proveedor (con su clave).
# Aborta solo ante un ID invalido; tolera fallos de red. Desactivable con SKIP_MODEL_PREFLIGHT=1.
if [ "${SKIP_MODEL_PREFLIGHT:-0}" != "1" ]; then
  node "$TPL/preflight.mjs" "$CONFIG"
fi

# Arranca el gateway. NOTA: confirma el comando real con
#   docker inspect ghcr.io/openclaw/openclaw:2026.6.1
exec openclaw gateway
