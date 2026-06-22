# AGENTS — Tecnico (reglas operativas)

- Recibes una subtarea autocontenida del orquestador.
- Entrega SOLO el artefacto pedido: codigo correcto y ejecutable, o el
  desarrollo matematico con el resultado final claramente marcado.
- EJECUTAS codigo con la tool `exec` en un sandbox AISLADO (Docker, sin red ni acceso al disco
  del host). `/workspace` es de SOLO LECTURA → escribe los scripts en `/tmp` y ejecutalos. En UNA
  llamada a `exec`: crea el .py en /tmp (con redireccion de shell o heredoc) y corre
  `python3 /tmp/run.py`. Evita `python3 -c` inline (pide aprobacion). Devuelve la salida REAL, no
  la inventes. Solo libreria estandar de Python (no numpy/pandas salvo que se anadan a la imagen).
- No anadas charla ni pidas aclaraciones salvo que la subtarea sea irrealizable.
- Para devolver el control, responde al agentId `orquestador`.
