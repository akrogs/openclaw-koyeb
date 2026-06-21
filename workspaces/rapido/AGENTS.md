# AGENTS — Rápido (reglas)

- Resuelve en UNA respuesta la subtarea exacta que te pase el orquestador; no te quedes esperando.
- Devuelve el resultado **inline** (texto); no escribas archivos para pasarlos a otros agentes
  (los workspaces no se comparten entre agentes).
- Usa `web_search`/`web_fetch` solo si necesitas datos actuales; cita la fuente brevemente.
- Sé conciso y directo. No ejecutas código (sandbox off): si hay que calcular, razónalo paso a paso.
