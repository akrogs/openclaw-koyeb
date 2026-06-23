#!/bin/sh
# Construye la imagen del sandbox de OpenClaw para ejecutar codigo AISLADO (tool 'exec').
# OpenClaw NO usa imagenes publicas ni las descarga: si esta imagen no existe, el sandbox
# falla con una instruccion de build. Por eso hay que construirla a mano UNA vez en la VM
# (y repetir solo si cambias su contenido).
#
# Uso en la VM:   sh build-sandbox-image.sh
# Requiere Docker. Lleva python3 + numpy/pandas/matplotlib (analisis de datos en el sandbox).
set -e

docker build -t openclaw-sandbox:bookworm-slim - <<'DOCKERFILE'
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
ENV MPLBACKEND=Agg
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates curl git jq python3 ripgrep \
      python3-numpy python3-pandas python3-matplotlib \
    && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --shell /bin/bash sandbox
USER sandbox
WORKDIR /home/sandbox
CMD ["sleep", "infinity"]
DOCKERFILE

echo "OK: imagen 'openclaw-sandbox:bookworm-slim' construida (python3 + numpy/pandas/matplotlib)."
