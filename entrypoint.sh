#!/bin/sh
set -e

# Directorio de configuracion de OpenClaw (montado como volumen persistente en Koyeb).
CONFIG_DIR="/home/node/.openclaw"
mkdir -p "$CONFIG_DIR/workspace"

# La configuracion de agentes es declarativa: se siembra/actualiza desde la plantilla
# del repo en cada arranque. Esto SOLO reescribe openclaw.json; los perfiles de auth y
# las aprobaciones de dispositivo (en $CONFIG_DIR/agents/...) se conservan intactos.
cp /opt/openclaw/openclaw.json "$CONFIG_DIR/openclaw.json"

# Arranca el gateway. NOTA: confirmar el comando real de la imagen oficial con
#   docker inspect ghcr.io/openclaw/openclaw:latest
# por si el CMD difiere de "openclaw gateway".
exec openclaw gateway
