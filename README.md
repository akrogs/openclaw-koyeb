# OpenClaw 24/7 — asistente multi-agente por Telegram (Docker, reproducible)

Despliegue reproducible de [OpenClaw](https://docs.openclaw.ai) con **4 agentes** especializados, chat
por **Telegram** (y opcionalmente la **app iOS**), ejecución de código **aislada**, visión, mapas,
memoria de largo plazo y búsqueda web. Todo horneado en la imagen (config + instrucciones + scripts) y
versionado en el repo: la VM solo hace `git pull && docker compose up -d --build`.

> El modelo principal es el **Z.ai GLM 5.2 Coding Plan** (de pago, cuota generosa); las cadenas de
> **fallback** son modelos **gratuitos** (NVIDIA / ZenMux / Cerebras / OpenRouter) para resistir 429 sin
> coste. La inferencia corre en los proveedores externos: el contenedor solo ejecuta el gateway (I/O
> ligero) → basta un **VPS de ~2 GB RAM**, sin GPU.

## Agentes

| Agente | Rol | Modelo primario | Fallbacks (cadena) |
|---|---|---|---|
| `orquestador` (default) | Recibe Telegram, descompone, delega e integra. Visión, mapas, memoria. | `zai/glm-5.2` (Coding Plan) | Kimi K2.6 → ZenMux GLM 5.2 free → MiniMax M3 → GLM 5.1 → Nemotron → OpenRouter free |
| `tecnico` | Código y matemáticas; **ejecuta Python** en sandbox aislado. | `zai/glm-5.2` | GLM 5.1 (NVIDIA) → ZenMux GLM 5.2 → Cerebras GPT-OSS → OpenRouter free |
| `formato` | Informes finales, JSON, limpiar texto. | `cerebras/gpt-oss-120b` | ZenMux GLM 5.2 → GLM 5.1 → OpenRouter free |
| `rapido` | Subtareas rápidas/generales. | `deepseek-v4-flash` (NVIDIA, free) | ZenMux GLM 5.2 → OpenRouter free |

- **Visión:** `agents.defaults.imageModel = Kimi K2.6` (con MiniMax de fallback). GLM 5.2 es solo texto,
  así que las **imágenes de Telegram se enrutan automáticamente a Kimi** mientras el texto va por GLM 5.2.
- El **rol/persona y la política de delegación** viven en `workspaces/<id>/{SOUL.md,AGENTS.md}` (OpenClaw
  los inyecta en el system prompt). La delegación usa `subagents.allowAgents` + `sessions_spawn`.
- **Proveedores:** `zai` (built-in, override de baseUrl al endpoint de coding), `nvidia`/`cerebras`/
  `zenmux` (custom OpenAI-compatible en `models.providers`), `openrouter` (nativo).

## Quickstart (cualquier VPS ≥2 GB, x86)

```sh
# 1) VM (Ubuntu): swap de seguridad + Docker
sudo apt-get update && sudo apt-get install -y git
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
curl -fsSL https://get.docker.com | sudo sh

# 2) Repo + secretos
git clone https://github.com/akrogs/openclaw-koyeb.git && cd openclaw-koyeb
cp .env.example .env && nano .env      # rellena las claves (ver abajo)

# 3) Imagen del sandbox de exec (una vez; lleva python3 + numpy/pandas/matplotlib)
sh build-sandbox-image.sh

# 4) Arranca
docker compose up -d --build
docker compose logs -f openclaw        # espera [preflight] OK y [gateway] ready
```

Acceso a la UI web (opcional): túnel SSH desde tu Mac → `ssh -L 18789:localhost:18789 root@IP` y abre
`http://localhost:18789`. Para la app iOS, ver "App iOS".

> ⚠️ **La config está horneada en la imagen** (el entrypoint la re-siembra en cada arranque). Cualquier
> cambio en `openclaw.json`/`workspaces/` requiere **`docker compose up -d --build`** (no basta `up -d`).

## Claves del `.env`

| Clave | Para qué | Coste |
|---|---|---|
| `ZAI_API_KEY` | **Primario** (GLM 5.2 Coding Plan) de orquestador y técnico. [z.ai](https://z.ai) | De pago (suscripción) |
| `NVIDIA_API_KEY` | Kimi (visión) + fallbacks + `rapido`. [build.nvidia.com](https://build.nvidia.com) | Gratis |
| `ZENMUX_API_KEY` | Fallback GLM 5.2 free. [zenmux.ai](https://zenmux.ai) | Gratis |
| `CEREBRAS_API_KEY` | Primario de `formato`. [cloud.cerebras.ai](https://cloud.cerebras.ai) | Gratis |
| `OPENROUTER_API_KEY` | Último fallback + modelos manuales. [openrouter.ai](https://openrouter.ai/keys) | Gratis/pago |
| `MISTRAL_API_KEY` | STT: transcribe notas de voz. [console.mistral.ai](https://console.mistral.ai) | Gratis |
| `KLAVIS_API_KEY` + `KLAVIS_STRATA_URL` | Calendar + Notion + Drive + memoria mem0 (MCP remoto). | Gratis |
| `TELEGRAM_BOT_TOKEN` + `TELEGRAM_ALLOW_FROM` | Bot (@BotFather) + tu ID numérico (@userinfobot). | Gratis |
| `OPENCLAW_GATEWAY_TOKEN` | Auth de la UI. `openssl rand -hex 32`. | — |
| `GOOGLE_MAPS_API_KEY` | (Opcional) Google Maps vía el orquestador. Restríngela por API + IP. | De pago (crédito gratis) |
| `TAVILY_API_KEY` | (Opcional) Búsqueda web de calidad. [tavily.com](https://tavily.com) | Gratis ~1k/mes |

`GEMINI_API_KEY`/`GROQ_API_KEY` ya **no se usan** (déjalas vacías).

## Capacidades

- **Ejecución de código (aislada):** `tecnico` ejecuta Python en un **sandbox Docker** (`sandbox.mode:
  all`, imagen `openclaw-sandbox:bookworm-slim` con numpy/pandas/matplotlib, `network: none`) → cálculos
  y análisis de datos reales, devueltos como texto/tablas. El orquestador también tiene `exec` (para las
  recetas de abajo).
- **Gráficas → Telegram:** el orquestador renderiza con matplotlib (en la imagen del gateway), guarda en
  `/tmp` y te envía la imagen (`message` + media).
- **Google Maps:** el orquestador hace `curl` a la API con `GOOGLE_MAPS_API_KEY` del entorno (geocoding,
  sitios+reseñas, rutas, imagen de mapa a `/tmp`). **Mapas ligeros gratis:** receta OSM/Nominatim por `web_fetch`.
- **Búsqueda web:** DuckDuckGo (`tools.web.search`) + skill `multi-search-engine` (16 motores) + skill
  `summarize` (resúmenes de URLs/artículos). Mejorable a **Tavily** (poner la key y `provider: "tavily"`).
- **Visión:** fotos de Telegram → Kimi (imageModel). **Voz:** notas de voz → texto (Mistral Voxtral).
- **Memoria:** largo plazo en **mem0** (vía Klavis, externo); notas locales en `MEMORY.md`.
- **Servicios (MCP Klavis Strata):** Google Calendar, Notion, Google Drive, mem0 — en un solo MCP remoto
  (0 RAM en la VM). Alta: crea la Strata con un POST y autoriza las cuentas en el navegador (ver más abajo).
- **Skills** (por agente en `agents.list[].skills`): `weather`, `diagram-maker`, `multi-search-engine`,
  `summarize`.
- **Automatización:** `cron` + `message` (p.ej. briefing diario proactivo), `goals`.

## Cambiar de modelo a mano (`/model`)

El orquestador va por `zai/glm-5.2`; puedes cambiar tu sesión a otros modelos registrados (no se usan en
automático):

```
/model zai/glm-4.7 · zai/glm-5-turbo · zai/glm-4.5-air        (Coding Plan)
/model openrouter/z-ai/glm-5.2                                (GLM 5.2, de pago)
/model openrouter/deepseek/deepseek-v4-pro                    (potente, de pago)
/model openrouter/deepseek/deepseek-v4-flash                  (rápido, de pago)
/model default                                                (vuelve a zai/glm-5.2)
```

Están en `agents.defaults.models` → disponibles para **todos** los agentes.

## Servicios externos (Klavis Strata): Calendario + Notion + Drive + mem0

Un único MCP remoto agrega las apps (corre en la nube de Klavis → 0 RAM/CPU local):

```sh
# 1) API key en klavis.ai. 2) Crea la Strata (devuelve strataServerUrl + oauthUrls):
curl -s -X POST https://api.klavis.ai/mcp-server/strata/create \
  -H "Authorization: Bearer KLAVIS_API_KEY" -H "Content-Type: application/json" \
  -d '{"userId":"akrogs","servers":["Google Calendar","Notion","Google Drive"],"enableAuthHandling":true}'
# 3) Abre los oauthUrls en el navegador y autoriza. 4) Pon KLAVIS_API_KEY + KLAVIS_STRATA_URL en .env.
```

Para **memoria semántica** (mem0), añade "Mem0" a la Strata y autorízalo con una key de mem0. Config:
`mcp.servers.klavis` (streamable-http). Las tools MCP se permiten por agente con `"klavis__*"` en `tools.allow`.

## App iOS de OpenClaw (nodo, vía Tailscale)

La app conecta al gateway por WebSocket. Como la VM es remota, se usa **Tailscale** (privado, `ws://` OK
en el tailnet, sin exponer nada público):

1. **VM:** `curl -fsSL https://tailscale.com/install.sh | sh && tailscale up`. Anota la IP `100.x`.
2. **VM `.env`:** `OPENCLAW_BIND=<ip-tailscale>` → `docker compose up -d` (publica 18789 solo en el tailnet).
3. **iPhone:** app **Tailscale** (mismo tailnet) + app **OpenClaw** → Settings → Gateway → host `<ip>:18789`.
4. **VM:** aprueba el nodo: `docker compose exec -u node openclaw env HOME=/home/node openclaw devices list`
   → `... openclaw devices approve <requestId>`. Verifica con `... openclaw nodes status`.

## Operación (robustez)

- **Reinicio:** `docker compose restart openclaw` (normal) · `up -d --build` (tras cambios) ·
  `down && up -d` (si se cuelga).
- **Watchdog auto-heal** (cron root cada 5 min): si `/readyz` no responde, `docker restart openclaw` + aviso
  por Telegram. Cubre el caso "vivo pero colgado" que `restart: unless-stopped` no detecta.
- **Backup semanal del volumen** (cron root): `docker run --rm -v openclaw-data:/data:ro -v /root/backups:/backup
  alpine tar czf /backup/openclaw-data-$(date +%F).tgz -C / data` (conserva 4). (Config y mem0 ya viven fuera.)
- **Límites:** `mem_limit: 1200m` + rotación de logs en el compose (protegen la VM de 2 GB).

## Estructura

```
openclaw-koyeb/
├── Dockerfile               # imagen 2026.6.1 + docker CLI + python/matplotlib + horneado de config/scripts
├── docker-compose.yml       # servicio openclaw (docker.sock para el sandbox, mem_limit, logs) + cloudflared
├── entrypoint.sh            # root: chown volumen + perms docker.sock + siembra config → baja a "node"
├── node-start.sh            # avisa de claves + preflight + arranca gateway
├── preflight.mjs            # valida IDs por proveedor (primario→error salvo warnOnly; fallback→aviso)
├── build-sandbox-image.sh   # construye openclaw-sandbox:bookworm-slim (python3+numpy/pandas/matplotlib)
├── openclaw.json            # 4 agentes, providers, imageModel, skills, modelos manuales, MCP Klavis, Telegram
├── workspaces/<id>/{SOUL.md,AGENTS.md}
├── .env.example
└── README.md
```

## Caveats

- **La config está horneada** → cambios en el repo requieren `up -d --build` (no `up -d`).
- **Los IDs de modelo cambian rápido** → por eso existe `preflight.mjs` (primario ausente = aborta, salvo
  `warnOnly`; fallback ausente = solo avisa). El proveedor `zai` es `warnOnly` (catálogo del Coding Plan sin
  confirmar) → nunca bloquea el arranque.
- **Custom providers = 2 pasos:** definir el provider **y** listar el modelo (o "model not allowed").
- **`exec` del orquestador NO está en sandbox** (corre en el contenedor del gateway, con acceso al
  `docker.sock` y al `.env`). Es un riesgo aceptado para las recetas de Maps/gráficas; una inyección de
  prompt podría abusarlo. Las **API keys son gratuitas/reemplazables** y la VM es desechable.
- **Entrega de archivos del sandbox:** el sandbox de `tecnico` está aislado y **no** entrega archivos (haría
  falta migrar el volumen a bind-mount). Por eso las gráficas las renderiza el **orquestador**.

## Fuentes

- [OpenClaw docs](https://docs.openclaw.ai) · [Model providers](https://docs.openclaw.ai/concepts/model-providers)
  · [Sandboxing](https://docs.openclaw.ai/gateway/sandboxing) · [iOS](https://docs.openclaw.ai/platforms/ios)
- [Z.ai](https://z.ai) · [NVIDIA build](https://build.nvidia.com) · [ZenMux](https://zenmux.ai) ·
  [Cerebras](https://cloud.cerebras.ai) · [OpenRouter](https://openrouter.ai) · [Klavis](https://klavis.ai)
