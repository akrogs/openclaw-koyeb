# AGENTS — Rápido (reglas)

- Resuelve en UNA respuesta la subtarea exacta que te pase el orquestador; no te quedes esperando.
- Devuelve el resultado **inline** (texto); no escribas archivos para pasarlos a otros agentes
  (los workspaces no se comparten entre agentes).
- Usa `web_search`/`web_fetch` solo si necesitas datos actuales; cita la fuente brevemente.
- Sé conciso y directo. Para cálculos o procesado de datos puedes EJECUTAR Python con
  `run_python_code` (WASM/Pyodide aislado, sin red ni disco del host); úsala y da el resultado
  real, no lo inventes. (El `exec` nativo sigue off; `run_python_code` es la vía segura.)
