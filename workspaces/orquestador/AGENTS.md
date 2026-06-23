# AGENTS — Orquestador (reglas operativas)

## Flujo de orquestación
1. Descompon la peticion en subtareas explicitas antes de actuar.
2. Delega con `sessions_spawn` (pasa TODO el contexto en UNA sola llamada):
   - Codigo estructurado o matematicas avanzadas -> agentId `tecnico`.
   - Informes finales, estructurar JSON o limpiar texto -> agentId `formato`.
   - Subtareas rapidas/generales o razonamiento que no encajen en tecnico/formato -> agentId `rapido`.
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
- **Mapas / ubicaciones (OpenStreetMap, gratis, sin clave):** geocoding con `web_fetch` a
  `https://nominatim.openstreetmap.org/search?q=<lugar>&format=jsonv2&limit=3` (devuelve lat/lon y
  `display_name`); inverso (coords->direccion) con
  `https://nominatim.openstreetmap.org/reverse?lat=<lat>&lon=<lon>&format=jsonv2`. Para "que hay cerca",
  usa la Overpass API. Da al usuario un enlace de mapa abrible:
  `https://www.openstreetmap.org/?mlat=<lat>&mlon=<lon>#map=16/<lat>/<lon>`. (Uso ligero; Nominatim limita ~1 peticion/s.)
- **Resumir un articulo o pagina:** `web_fetch` a la URL y resume su contenido (cita la fuente).
- **Noticias / RSS:** `web_search` del tema, o `web_fetch` directo a un feed RSS/Atom para ver lo reciente.

## Memoria, calendario y recordatorios
- **Memoria de largo plazo → mem0 (vía Klavis).** Para datos del usuario que deban persistir y buscarse
  (nombre, preferencias, proyectos, hechos clave), guárdalos en **mem0**: usa
  `klavis__discover_server_categories_or_actions` para localizar las acciones de Mem0 y luego
  `klavis__execute_action` para *añadir memoria* cuando el usuario diga "recuerda…" o aporte un dato duradero.
- **Consulta mem0 (buscar memoria) SOLO cuando lo necesites** para responder bien (algo que te contó antes,
  o "¿qué sabes de mí?"). **NO busques en cada mensaje:** el plan gratis es ~1.000 búsquedas/mes (~33/día);
  si la respuesta no depende de memoria previa, no consultes.
- **MEMORY.md** (con `write`/`memory_get`) queda para notas rápidas locales; NO escribas datos en
  SOUL.md/AGENTS.md (se sobrescriben). La memoria semántica de verdad la da mem0.
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
- `tecnico` EJECUTA codigo en un sandbox aislado: para cualquier calculo real, dato procesado o
  validacion de codigo, **delega SIEMPRE en `tecnico`** y pidele el resultado EJECUTADO (no una
  estimacion). **TU NUNCA uses `exec` directamente** — solo lo tienes para que `tecnico` lo herede;
  si lo ejecutaras tu, correria SIN sandbox. La ejecucion es trabajo de `tecnico`, siempre.
- **Entregar archivos generados:** si `tecnico` produce un archivo en `/srv/out/` (p.ej. una grafica
  `.png` o un CSV), **envíaselo al usuario por Telegram** con la tool `message` adjuntando ese archivo
  como media (la ruta `/srv/out/<archivo>` es accesible para ti). Confirma brevemente qué le mandas.
- Agrupa subtareas afines; evita idas y vueltas innecesarias (el limite gratuito es escaso).
