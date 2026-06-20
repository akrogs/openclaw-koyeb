# OpenClaw en Koyeb — 3 agentes con modelos gratuitos (multi-proveedor)

Despliegue reproducible de [OpenClaw](https://docs.openclaw.ai) en [Koyeb](https://www.koyeb.com)
con tres agentes especializados, **cada uno en un proveedor gratuito distinto** para tener cuotas de
rate limit independientes.

## Arquitectura de agentes

| Agente | Rol | Proveedor → Modelo (free) | Límite free |
|---|---|---|---|
| `orquestador` (default) | Divide el problema en subtareas, gestiona el contexto masivo y delega. | **Google** → `google/gemini-2.5-flash` | ~1.500 req/día, 1M ctx |
| `tecnico` | Código estructurado y matemáticas avanzadas. | **Groq** → `groq/openai/gpt-oss-120b` | ~14.4k req/día |
| `formato` | Informes finales, estructurar JSON y limpiar texto. | **Cerebras** → `cerebras/llama-3.3-70b` | 1M tok/día |

> **Por qué multi-proveedor:** los modelos `:free` de OpenRouter comparten ~50 req/día **por cuenta**.
> Asignando un proveedor por agente, cada uno tiene su propia cuota y el mejor modelo para su rol. Cada
> agente tiene además un *fallback* en otro proveedor gratuito.

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
├── entrypoint.sh         # root: chown del volumen + siembra config → baja a "node"
├── node-start.sh         # node: avisa de claves + preflight + arranca gateway
├── preflight.mjs         # valida los IDs de modelos contra Google/Groq/Cerebras
├── openclaw.json         # config de los 3 agentes + models.providers (groq, cerebras)
├── workspaces/
│   ├── orquestador/{SOUL.md,AGENTS.md}   # persona + política de delegación
│   ├── tecnico/{SOUL.md,AGENTS.md}
│   └── formato/{SOUL.md,AGENTS.md}
├── .env.example
└── README.md
```

## Despliegue en Koyeb

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

## Caveats

- **Los IDs de modelos cambian rápido — por eso existe el preflight.** Confirma en cada proveedor:
  - **Groq deprecó `llama-3.3-70b-versatile` y `llama-3.1-8b-instant` el 17-jun-2026** → usamos
    `openai/gpt-oss-120b` / `qwen/qwen3-32b` en Groq, y Llama 3.3 70B desde **Cerebras** (estable allí).
  - **Cerebras `qwen-3-coder-480b` es "evaluation"** (puede retirarse) → va como *fallback*; el preflight avisa.
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
