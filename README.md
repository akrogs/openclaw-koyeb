# OpenClaw 24/7 — 3 agentes con modelos gratuitos (multi-proveedor)

Despliegue reproducible de [OpenClaw](https://docs.openclaw.ai) (Docker) con tres agentes especializados,
**cada uno en un proveedor gratuito distinto** para tener cuotas de rate limit independientes.

> ⚠️ **Koyeb cerró su free tier para cuentas nuevas** (adquisición por Mistral AI, feb-2026). El despliegue
> **gratis** recomendado es **Google Cloud e2-micro Always Free** con `docker-compose` (Opción A); Oracle
> Always Free (Opción B) también vale pero su capacidad gratuita suele estar agotada por región. Koyeb
> (Opción C) ya es de pago. Las tres usan el **mismo `docker-compose`** salvo el alta de la VM.

## Arquitectura de agentes

| Agente | Rol | Proveedor → Modelo (free) | Límite free |
|---|---|---|---|
| `orquestador` (default) | Divide el problema en subtareas, gestiona el contexto masivo y delega. | **Google** → `google/gemini-2.5-flash` | ~1.500 req/día, 1M ctx |
| `tecnico` | Código estructurado y matemáticas avanzadas. | **Groq** → `groq/openai/gpt-oss-120b` | ~14.4k req/día |
| `formato` | Informes finales, estructurar JSON y limpiar texto. | **Cerebras** → `cerebras/llama-3.3-70b` | 1M tok/día |

> **Por qué multi-proveedor:** los modelos `:free` de OpenRouter comparten ~50 req/día **por cuenta**.
> Asignando un proveedor por agente, cada uno tiene su propia cuota y el mejor modelo para su rol. Cada
> agente tiene además un *fallback* en otro proveedor gratuito.

> 🛠️ **Config activa (temporal):** el alta de **Groq** está fallando (error de signup en su web), así que
> `openclaw.json` usa **solo Google + Cerebras** por ahora — `tecnico` corre en `cerebras/gpt-oss-120b` y
> `formato` en `cerebras/zai-glm-4.7` (IDs reales del catálogo de Cerebras). **Para reactivar Groq** cuando
> funcione: añade `GROQ_API_KEY` al `.env`, vuelve a declarar el provider `groq` en `models.providers` y pon
> `tecnico.model.primary` a `groq/openai/gpt-oss-120b` (todo está en el historial git / commit `151363f`).

```
        Web Control UI (Koyeb :18789)
                  │
            ┌─────▼──────┐
            │ orquestador│  Google Gemini 2.5 Flash (thinking=high)
            └──┬──────┬──┘
   sessions_spawn│      │sessions_spawn
        ┌────────▼┐   ┌─▼────────┐
        │ tecnico │   │ formato  │
        │ Groq    │   │ Cerebras │
        │ GPT-OSS │   │ Llama3.3 │
        └─────────┘   └──────────┘
  (cuotas independientes: 1 proveedor por agente)
```

El **rol y la política de delegación** de cada agente se definen en `workspaces/<id>/SOUL.md` (persona) y
`AGENTS.md` (reglas), que OpenClaw inyecta en el system prompt. La delegación usa `subagents.allowAgents`
+ `sessions_spawn`. Google es proveedor **nativo** de OpenClaw; Groq y Cerebras se configuran como
**custom providers** (OpenAI-compatible) en `models.providers` de `openclaw.json`.

> La inferencia LLM corre en los proveedores externos, **no** en Koyeb. El contenedor solo ejecuta el
> gateway (proceso ligero de I/O): basta una instancia pequeña (~0.5–1 GB RAM), sin GPU.

## Estructura

```
openclaw-koyeb/
├── Dockerfile            # imagen fijada (2026.6.1) + hornea config/instrucciones/scripts
├── docker-compose.yml    # despliegue 24/7 en una VM (Oracle/local) + túnel Cloudflare opcional
├── entrypoint.sh         # root: chown del volumen + siembra config → baja a "node"
├── node-start.sh         # node: avisa de claves + preflight + arranca gateway
├── preflight.mjs         # valida IDs contra Google/Groq/Cerebras (primario→error, fallback→aviso)
├── openclaw.json         # config de los 3 agentes + models.providers + web search + Telegram
├── workspaces/
│   ├── orquestador/{SOUL.md,AGENTS.md}   # persona + política de delegación
│   ├── tecnico/{SOUL.md,AGENTS.md}
│   └── formato/{SOUL.md,AGENTS.md}
├── .env.example
└── README.md
```

## Opción A — Google Cloud e2-micro Always Free (gratis, `docker-compose`)

VM *always-free* fiable (sin la lotería de capacidad de Oracle) y x86 (sin líos de arquitectura ARM).

> ⚠️ **Para que sea $0**, respeta los límites del free tier: **1 `e2-micro`** en **us-west1 / us-central1 /
> us-east1**, disco **Standard (pd-standard) ≤ 30 GB**, y ~1 GB de egress/mes. SSD/balanced o >30 GB se cobra.
> El **estimador de la consola muestra el precio de lista (~$7/mes) y NO resta el Always Free** — el e2-micro
> elegible se factura y se descuenta a $0. Lo único a vigilar: que el disco de arranque sea **Estándar**
> (el "balanceado" por defecto sí cobra ~$1/mes). Opcional: crea una alerta de presupuesto de $1.

1. **Crea la VM** en [console.cloud.google.com](https://console.cloud.google.com) → Compute Engine → VM
   instances → **Create**:
   - **Region:** `us-central1` (Iowa). **Machine type:** serie **E2** → **`e2-micro`** (2 vCPU / 1 GB).
   - **Boot disk:** **Ubuntu 22.04 LTS**, tipo **Standard persistent disk**, **30 GB**.
   - Crea. (No hace falta abrir puertos si usas Cloudflare Tunnel o port-forward por SSH.)
2. **Conéctate por SSH** (botón **SSH** del navegador, o `gcloud compute ssh <vm> --zone us-central1-a`).
3. **Crea swap (1 GB de RAM) e instala Docker:**
   ```sh
   # En imágenes "Minimal" instala primero git/curl:
   sudo apt-get update && sudo apt-get install -y git curl
   sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
   echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
   curl -fsSL https://get.docker.com | sudo sh
   sudo usermod -aG docker $USER && newgrp docker
   ```
4. **Clona el repo, configura secretos y arranca:**
   ```sh
   git clone https://github.com/akrogs/openclaw-koyeb.git && cd openclaw-koyeb
   cp .env.example .env && nano .env     # GEMINI/GROQ/CEREBRAS + OPENCLAW_GATEWAY_TOKEN (openssl rand -hex 32)
   docker compose up -d --build
   docker compose logs -f openclaw       # verifica el preflight y el arranque
   ```
5. **Accede a la UI:**
   - Sin abrir puertos (recomendado): port-forward por SSH desde tu Mac:
     `gcloud compute ssh <vm> --zone us-central1-a -- -L 18789:127.0.0.1:18789` → abre `http://localhost:18789`.
   - Permanente con HTTPS: **Cloudflare Tunnel** (perfil `tunnel` del compose).
   - Directo: crea una *firewall rule* `tcp:18789` y pon `ports: ["18789:18789"]` en el compose.
6. **Aprueba el dispositivo:** pega el `OPENCLAW_GATEWAY_TOKEN` en la UI → Connect, y aprueba desde el
   contenedor (`docker compose exec openclaw openclaw devices approve`, o el comando que indique la UI).

---

## Opción B — Oracle Cloud Always Free (si hay capacidad)

VM gratuita y *always-on* con volumen persistente. Misma idea que la Opción A (mismo `docker-compose`).

> ⚠️ **Capacidad:** el free tier de Oracle suele dar **"Out of host capacity"** (ARM **y** AMD) en muchas
> regiones, y la *home region* es fija. El truco habitual: **subir a Pay As You Go** da prioridad de
> capacidad y los recursos *Always Free* siguen a **$0** mientras no superes los límites (requiere tarjeta).

1. **Crea la VM** en [cloud.oracle.com](https://cloud.oracle.com) → Compute → Instances → Create:
   - Shape recomendado: **VM.Standard.E2.1.Micro** (AMD x86, 1 OCPU / 1 GB) *Always Free* — **casi siempre
     disponible** y evita el lío de arquitectura ARM. Imagen: **Ubuntu 22.04**. Guarda la **clave SSH**.
   - *(Alternativa con más RAM: shape **Ampere A1 (ARM)** Always Free — pero suele dar "Out of capacity" en
     muchas regiones, Madrid incluida; tu home region es fija y no se cambia para el free tier.)*
2. **Abre el acceso:** si vas a usar Cloudflare Tunnel, **no** abras puertos. Si quieres acceso directo,
   abre el 18789 en la *Security List* de la VCN **y** en el firewall de la VM (`ufw`/`iptables`).
3. **Entra por SSH, crea swap (la Micro tiene solo 1 GB) e instala Docker:**
   ```sh
   ssh ubuntu@<IP>
   sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
   echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
   curl -fsSL https://get.docker.com | sudo sh
   sudo usermod -aG docker $USER && newgrp docker
   ```
4. **Clona el repo** (privado → usa un PAT de GitHub o `gh auth login`):
   ```sh
   git clone https://github.com/akrogs/openclaw-koyeb.git
   cd openclaw-koyeb
   ```
5. **Configura los secretos:**
   ```sh
   cp .env.example .env
   nano .env        # pon GEMINI/GROQ/CEREBRAS y OPENCLAW_GATEWAY_TOKEN (openssl rand -hex 32)
   ```
6. **Arranca 24/7:**
   ```sh
   docker compose up -d --build
   docker compose logs -f openclaw      # verifica el preflight y el arranque
   ```
7. **Acceso:**
   - Rápido (sin abrir puertos): túnel SSH → `ssh -L 18789:127.0.0.1:18789 ubuntu@<IP>` y abre
     `http://localhost:18789` en tu Mac.
   - Permanente con HTTPS (gratis): crea un tunnel en Cloudflare, pon `CLOUDFLARE_TUNNEL_TOKEN` en `.env`,
     enruta tu hostname → `http://openclaw:18789` y `docker compose --profile tunnel up -d`.
8. **Aprueba el dispositivo:** abre la UI, pega el `OPENCLAW_GATEWAY_TOKEN` → Connect, y aprueba el
   dispositivo desde el contenedor: `docker compose exec openclaw openclaw devices approve` (o el comando
   que indique la UI).

> ⚠️ **Arquitectura:** con la **Micro AMD (x86)** no hay problema — la imagen base tiene amd64. Solo si usas
> el shape **ARM A1** necesitas que `ghcr.io/openclaw/openclaw:2026.6.1` tenga variante **arm64**; si el
> build falla por arquitectura, vuelve a la Micro AMD.

---

## Opción C — Koyeb (de pago para cuentas nuevas)

1. **Sube este repo a GitHub.**
2. **Genera el gateway token:** `openssl rand -hex 32`.
3. **Crea 3 API keys gratuitas:**
   - Google AI Studio → https://aistudio.google.com
   - Groq → https://console.groq.com
   - Cerebras → https://cloud.cerebras.ai
4. En Koyeb: **Create Service → Deploy from GitHub**, selecciona el repo. Build = **Dockerfile**.
5. **Instancia:** la más pequeña disponible (eco/nano, ~512 MB). **Min = 1 instancia, sin scale-to-zero**
   (el volumen ata a una sola instancia y scale-to-zero tiraría la sesión del gateway).
6. **Puerto:** expón **`18789`** como puerto público. Health checks HTTP: `/healthz` y `/readyz`.
7. **Secrets (variables de entorno):**
   - `GEMINI_API_KEY`, `GROQ_API_KEY`, `CEREBRAS_API_KEY`
   - `OPENCLAW_GATEWAY_TOKEN`
   - *(opcional)* `SKIP_MODEL_PREFLIGHT=1`
8. **Volumen persistente:** crea un **Koyeb Volume** montado en **`/home/node/.openclaw`**. El
   `entrypoint.sh` ajusta su propiedad (corre como root y luego baja a `node`), reescribe `openclaw.json`
   desde el repo y siembra los `SOUL.md/AGENTS.md` **solo si no existen** (no pisa la memoria del agente).
9. **Despliega** y espera a que `/readyz` devuelva 200.
10. **Aprueba el dispositivo** (paso obligatorio post-deploy):
    - Abre `https://<service>.koyeb.app/overview`.
    - Introduce el `OPENCLAW_GATEWAY_TOKEN` y pulsa **Connect**.
    - En Koyeb → pestaña **Console** del servicio → ejecuta el comando que aprueba el dispositivo pendiente.

> Auth de proveedores: **no requiere `auth set` manual**. `GEMINI_API_KEY` lo consume el proveedor nativo
> `google`; `GROQ_API_KEY`/`CEREBRAS_API_KEY` se referencian con `${...}` en `models.providers`.

## Verificación

- `curl https://<service>.koyeb.app/healthz` y `/readyz` → 200.
- En los logs de arranque: `[preflight] google/groq/cerebras: N modelo(s) comprobado(s)` y `OK`.
- La Web UI carga, el token conecta y el dispositivo queda aprobado.
- En la Console: `openclaw agents list` (o equivalente) muestra `orquestador`, `tecnico`, `formato`.
- **Prueba de orquestación** (chat con `orquestador`):
  > "Calcula la serie de Fibonacci hasta n=20 en Python y entrégame un informe final en JSON con el código y los resultados."

  Esperado: el `orquestador` delega la generación de código a `tecnico` (Groq) y la redacción del JSON
  final a `formato` (Cerebras), visible en las trazas de subagentes.

## Verificar los modelos sin desplegar

El preflight se puede ejecutar en local con las claves exportadas (requiere Node 18+):
```sh
GEMINI_API_KEY=... GROQ_API_KEY=... CEREBRAS_API_KEY=... node preflight.mjs openclaw.json
```
Sin claves, el preflight avisa y omite cada proveedor (no falla).

## Hablar con el orquestador desde el móvil (Telegram)

El gateway se conecta a Telegram por *long-polling* (salida), así que funciona con el firewall cerrado y
detrás de Tailscale — no hay que abrir nada. Solo el dueño (tu ID) puede usar el bot (`dmPolicy: allowlist`).

1. **Crea el bot:** en Telegram escribe a **@BotFather** → `/newbot` → sigue los pasos → copia el **token**.
2. **Tu ID numérico:** escribe a **@userinfobot** → te responde con tu `Id` (p. ej. `123456789`).
3. **Rellena `.env`** en la VM:
   ```sh
   cd ~/openclaw-koyeb
   nano .env    # TELEGRAM_BOT_TOKEN=<token de BotFather>  ·  TELEGRAM_ALLOW_FROM=<tu id numérico>
   ```
4. **Aplica y arranca:**
   ```sh
   git pull
   docker compose up -d --build
   docker compose logs -f openclaw    # comprueba que el canal telegram conecta
   ```
5. **Escribe a tu bot** desde el iPhone → hablas con el **orquestador** (que delega en `tecnico`/`formato`).

> Config: `channels.telegram` (allowlist) + `bindings` (telegram → `orquestador`) en `openclaw.json`; token e
> ID van por `.env` (fuera del repo). Si el bot te ignora, confirma que `TELEGRAM_ALLOW_FROM` es tu ID
> numérico exacto (míralo como `from.id` en el log).

## Búsqueda web (DuckDuckGo, gratis)

El orquestador busca en internet con `web_search`/`web_fetch` usando **DuckDuckGo** — **gratis, sin clave,
sin contenedor extra**. Config: `tools.web.search.provider: "duckduckgo"`.

- No se usan Brave (ya no es gratis) ni el *grounding* de Gemini (puede facturar).
- **Por qué DuckDuckGo y no SearXNG:** SearXNG self-hosted es más robusto, pero no cabe junto a OpenClaw en
  la **e2-micro de 1 GB** (saturaba la RAM). Si subes a una VM con ≥2 GB, se puede volver a SearXNG
  (provider `searxng` + servicio en el compose).
- DuckDuckGo es un proveedor *experimental* (scrapea DDG): puede fallar ocasionalmente por páginas anti-bot.

## Servicios externos: Calendario + Notion + Drive (vía Klavis Strata, UN solo MCP)

El agente accede a **Google Calendar**, **Notion** (proyectos/tareas) y **Google Drive** (15 GB) por **un
único MCP remoto** ([Klavis **Strata**](https://klavis.ai)) — corre en su nube → **0 RAM/CPU en la VM y sin
`exec`**. Strata agrega las 3 apps en **una sola URL estable** (determinista por `userId`), autenticada con
**tu API key** (cabecera Bearer). (Se eligió Klavis sobre Composio porque el Tool Router de Composio genera
URLs por SDK/OAuth, que no encajan con la config estática de OpenClaw.)

**1. API key:** crea cuenta free en **klavis.ai** y copia tu **API key**.

**2. Crea la Strata (UN solo POST):** devuelve la `strataServerUrl` (una, estable) y los `oauthUrls`/`apiKeyUrls`
para autorizar cada cuenta:
```sh
curl -s -X POST https://api.klavis.ai/mcp-server/strata/create \
  -H "Authorization: Bearer KLAVIS_API_KEY" -H "Content-Type: application/json" \
  -d '{"userId":"akrogs","servers":["Google Calendar","Notion","Google Drive"],"enableAuthHandling":true}'
```

**3. Autoriza las cuentas:** abre en el navegador los `oauthUrls`/`apiKeyUrls` de la respuesta (Google,
Notion) y concede acceso. (El OAuth se hace en tu navegador, no en la VM.)

**4. Pon la API key y la URL en `.env`** y arranca:
```sh
cd ~/openclaw-koyeb
nano .env        # KLAVIS_API_KEY=...   KLAVIS_STRATA_URL=<strataServerUrl>
git pull
docker compose up -d --build
docker compose logs openclaw | grep -i -E "mcp|klavis"   # el server 'klavis' debe CONECTAR
```

> Config en `openclaw.json`: `mcp.servers.klavis` (`transport: streamable-http`, `url: ${KLAVIS_STRATA_URL}`,
> header `Authorization: Bearer ${KLAVIS_API_KEY}`). **Un solo MCP** para las 3 apps. MCP **remoto** → no añade
> RAM. **Ojo:** en 2026.6.1 las tools MCP SÍ pasan por el `tools.allow` del agente → el orquestador las
> permite con `"klavis__*"` (los 6 meta-tools de Strata: discover/execute/...). Pruébalo por Telegram:
> *"¿qué tengo en el calendario?"*, *"crea una tarea en Notion: …"*.

## Caveats

- **Los IDs de modelos cambian rápido — por eso existe el preflight.** Confirma en cada proveedor:
  - **Groq deprecó `llama-3.3-70b-versatile` y `llama-3.1-8b-instant` el 17-jun-2026** → usamos
    `openai/gpt-oss-120b` / `qwen/qwen3-32b` en Groq, y Llama 3.3 70B desde **Cerebras** (estable allí).
  - **Cerebras `qwen-3-coder-480b` es "evaluation"** (puede retirarse) → va como *fallback*; si desaparece
    el preflight **solo avisa** (no bloquea el arranque). Si falta un modelo **primario**, sí aborta.
  - **Gemini Pro NO es generoso en free** (~50 req/día) → el orquestador usa **Flash**, no Pro.
- **Rate limits independientes pero finitos:** mantén fallbacks, `maxPingPongTurns` y la regla "una
  llamada por subagente" del `AGENTS.md` del orquestador.
- **Custom providers = config de dos pasos:** definir el proveedor **y** listar el modelo en
  `models.providers[].models`, o saldrá "model not allowed".
- **Privacidad:** el free tier de Google AI Studio puede usar datos para mejorar el producto; evita datos
  sensibles o usa un tier que no entrene con tus datos.
- **Ejecución de código:** `tecnico` está en `sandbox: off` (Koyeb no expone socket Docker). Sirve para
  *escribir* código; ejecutarlo de forma segura requeriría otra solución de sandbox.
- **Imagen oficial:** confirma el CMD/entrypoint real de `ghcr.io/openclaw/openclaw:2026.6.1` y el formato
  exacto de `models.providers` de tu versión con `docker inspect` / la doc.

## Fuentes

- [OpenClaw — Model providers](https://docs.openclaw.ai/concepts/model-providers)
- [OpenClaw — Configuration: agents](https://docs.openclaw.ai/gateway/config-agents)
- [OpenClaw — Agent runtime](https://docs.openclaw.ai/concepts/agent) · [System prompt](https://docs.openclaw.ai/concepts/system-prompt)
- [OpenClaw — Docker install](https://docs.openclaw.ai/install/docker)
- [Deploy OpenClaw One-Click App — Koyeb](https://www.koyeb.com/deploy/openclaw)
- [Google AI Studio](https://ai.google.dev) · [Groq Docs](https://console.groq.com/docs) · [Cerebras Inference Docs](https://inference-docs.cerebras.ai)
