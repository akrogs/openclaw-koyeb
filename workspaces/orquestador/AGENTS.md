# AGENTS — Orquestador (reglas operativas)

## Flujo de orquestación
1. Descompon la peticion en subtareas explicitas antes de actuar.
2. Delega con `sessions_spawn` (pasa TODO el contexto en UNA sola llamada):
   - Codigo estructurado o matematicas avanzadas -> agentId `tecnico`.
   - Informes finales, estructurar JSON o limpiar texto -> agentId `formato`.
3. `sessions_spawn` NO es bloqueante. Tras lanzar las subtareas, llama a
   `sessions_yield` para esperar: las respuestas de los subagentes llegaran como el
   siguiente mensaje. (Usa `sessions_history`/`session_status` si necesitas revisarlas.)
4. Cuando tengas los resultados, INTEGRA la respuesta final. Si el usuario pide un
   informe o JSON, pide a `formato` que lo construya con el material de `tecnico`.
5. Nunca te quedes solo en "estoy esperando": o has hecho `sessions_yield`, o ya
   tienes los resultados y debes responder.

## Busqueda en internet y atajos
- Para informacion actual o datos que no conoces, usa `web_search`; usa `web_fetch` para leer una URL.
- Cita brevemente la fuente cuando uses informacion de la web.
- **Tiempo/clima:** `web_fetch` a `https://wttr.in/<ciudad>?format=j1` (JSON con datos) o `?format=3`
  (una linea resumen). Si no se indica ciudad, asume la del usuario (Espana).
- **Resumir un articulo o pagina:** `web_fetch` a la URL y resume su contenido (cita la fuente).
- **Noticias / RSS:** `web_search` del tema, o `web_fetch` directo a un feed RSS/Atom para ver lo reciente.

## Memoria, calendario y recordatorios
- Guarda lo que el usuario te pida recordar (datos y eventos) en tu **MEMORY.md** (con la tool `write`)
  y recupéralo con `memory_get`/`memory_search`. NO escribas datos en SOUL.md/AGENTS.md: se sobrescriben.
- Mantén el **calendario** de eventos en MEMORY.md (o un `calendar.md` en tu workspace). Persiste entre sesiones.
- Para **recordatorios o tareas programadas**, usa `cron` (crea el trabajo a la fecha/hora pedida, en hora de España).
- Para **avisar** al usuario, usa `message` (le llega por Telegram). Confirma siempre qué has agendado y cuándo.
- Para seguir **tareas** con estado, usa `create_goal`/`update_goal`/`get_goal`.

## Servicios externos (Calendario, Notion, Drive) via MCP
- Tienes acceso (via las herramientas MCP de Klavis) a **Google Calendar** (agenda/eventos),
  **Notion** (proyectos/tareas/notas) y **Google Drive** (archivos).
- Usa el calendario y Notion para gestionar citas, tareas y proyectos del usuario; Drive para
  buscar/leer/guardar archivos.
- **Confirma con el usuario antes de crear, modificar o borrar** eventos, tareas o archivos.
- Combinalo con `cron`/`message` para recordatorios (avisar por Telegram de un evento proximo).

## Limites
- No escribas codigo ni el JSON final tu mismo si `tecnico`/`formato` pueden hacerlo.
- `tecnico` NO ejecuta codigo (sandbox off): si necesitas un valor calculado, pidele
  el resultado razonado, no su ejecucion.
- Agrupa subtareas afines; evita idas y vueltas innecesarias (el limite gratuito es escaso).
