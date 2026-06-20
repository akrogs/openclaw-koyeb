# OpenClaw en Koyeb — 3 agentes con modelos gratuitos de OpenRouter

Despliegue reproducible de [OpenClaw](https://docs.openclaw.ai) en [Koyeb](https://www.koyeb.com)
con tres agentes especializados que enrutan a modelos **gratuitos** de OpenRouter.

## Arquitectura de agentes

| Agente | Rol | Modelo (free) — verificado en OpenRouter |
|---|---|---|
| `orquestador` (default) | Agente principal: divide el problema en subtareas, gestiona el contexto masivo y delega. | **Nemotron 3 Ultra** — `openrouter/nvidia/nemotron-3-ultra-550b-a55b:free` |
| `tecnico` | Tareas técnicas aisladas: código estructurado y matemáticas avanzadas. | **Qwen3 Coder** — `openrouter/qwen/qwen3-coder:free` (1M ctx) |
| `formato` | Informes finales, estructurar JSON y limpiar texto. | **Llama 3.3 70B** — `openrouter/meta-llama/llama-3.3-70b-instruct:free` |

> **Nota sobre el modelo técnico:** el objetivo inicial (Qwen 2.5 72B *free*) **ya no existe** en
> OpenRouter (solo de pago). Se usa **Qwen3 Coder** (gratis, 1M de contexto, especializado en código),
> fiel a la intención original. Cada agente tiene además un *fallback* gratuito.

```
        Web Control UI (Koyeb :18789)
                  │
            ┌─────▼──────┐
            │ orquestador│  Nemotron 3 Ultra (thinking=high)
            └──┬──────┬──┘
   sessions_spawn│      │sessions_spawn
        ┌────────▼┐   ┌─▼────────┐
        │ tecnico │   │ formato  │
        │ Qwen3   │   │ Llama3.3 │
        │ Coder   │   │          │
        └─────────┘   └──────────┘
```

El **rol y la política de delegación** de cada agente se definen en `workspaces/<id>/SOUL.md` (persona) y
`AGENTS.md` (reglas operativas), que OpenClaw inyecta en el system prompt. La delegación usa
`subagents.allowAgents` + `sessions_spawn`. Cada modelo tiene un **fallback gratuito** para resistir 429.

> La inferencia LLM corre en OpenRouter, **no** en Koyeb. El contenedor solo ejecuta el gateway
> (proceso ligero de I/O): basta una instancia pequeña (~0.5–1 GB RAM), sin GPU.

## Estructura

```
openclaw-koyeb/
├── Dockerfile            # imagen fijada (2026.6.1) + hornea config/instrucciones/scripts
├── entrypoint.sh         # root: chown del volumen + siembra config → baja a "node"
├── node-start.sh         # node: registra auth OpenRouter + preflight + arranca gateway
├── preflight.mjs         # valida que los slugs :free existen y son gratis (OpenRouter API)
├── openclaw.json         # config declarativa de los 3 agentes
├── workspaces/
│   ├── orquestador/{SOUL.md,AGENTS.md}   # persona + política de delegación
│   ├── tecnico/{SOUL.md,AGENTS.md}
│   └── formato/{SOUL.md,AGENTS.md}
├── .env.example
└── README.md
```

## Despliegue en Koyeb

1. **Sube este repo a GitHub.**
2. **Genera el gateway token:**
   ```sh
   openssl rand -hex 32
   ```
3. **Crea una API key de OpenRouter** en https://openrouter.ai/keys.
4. En Koyeb: **Create Service → Deploy from GitHub**, selecciona el repo. Build = **Dockerfile**.
5. **Instancia:** la más pequeña disponible (eco/nano, ~512 MB). **Min = 1 instancia, sin scale-to-zero**
   (el volumen ata a una sola instancia y scale-to-zero tiraría la sesión del gateway).
6. **Puerto:** expón **`18789`** como puerto público. Health checks HTTP: `/healthz` (liveness) y
   `/readyz` (readiness).
7. **Secrets (variables de entorno):**
   - `OPENROUTER_API_KEY`  ← el `node-start.sh` lo registra como perfil de auth al arrancar.
   - `OPENCLAW_GATEWAY_TOKEN`
   - *(opcional)* `SKIP_MODEL_PREFLIGHT=1` para saltar la verificación de modelos.
8. **Volumen persistente:** crea un **Koyeb Volume** montado en **`/home/node/.openclaw`**. El
   `entrypoint.sh` ajusta su propiedad (corre como root y luego baja a `node`), reescribe `openclaw.json`
   desde el repo y siembra los `SOUL.md/AGENTS.md` **solo si no existen** (no pisa la memoria del agente).
9. **Despliega** y espera a que `/readyz` devuelva 200.
10. **Aprueba el dispositivo** (paso obligatorio post-deploy):
    - Abre `https://<service>.koyeb.app/overview`.
    - Introduce el `OPENCLAW_GATEWAY_TOKEN` y pulsa **Connect**.
    - En Koyeb → pestaña **Console** del servicio → ejecuta el comando que aprueba el dispositivo pendiente.

> La auth de OpenRouter se registra automáticamente en el arranque. Si el subcomando real difiere,
> confírmalo con `openclaw auth --help` en la Console y ajusta `node-start.sh`.

## Verificación

- `curl https://<service>.koyeb.app/healthz` y `/readyz` → 200.
- En los logs de arranque: `[preflight] OK: 5 modelos verificados.`
- La Web UI carga, el token conecta y el dispositivo queda aprobado.
- En la Console: `openclaw agents list` (o equivalente) muestra `orquestador`, `tecnico`, `formato`.
- **Prueba de orquestación** (chat con `orquestador` en la Web UI):
  > "Calcula la serie de Fibonacci hasta n=20 en Python y entrégame un informe final en JSON con el código y los resultados."

  Esperado: el `orquestador` delega la generación de código a `tecnico` (Qwen3 Coder) y la redacción del
  JSON final a `formato` (Llama), visible en las trazas de subagentes.

## Verificar los modelos sin desplegar

El preflight se puede ejecutar en local (requiere Node 18+):
```sh
node preflight.mjs openclaw.json
```

## Caveats

- **Rate limits gratuitos (por cuenta, no por modelo):** ~50 req/día sin crédito (≈1000/día con $10) y
  pocos req/min. Usar 3 modelos **no** triplica el tope. Un orquestador que abre 2 subagentes gasta ≥3
  llamadas por petición. Mitigado con fallbacks, `maxPingPongTurns` y la regla de "una llamada por
  subagente" en `AGENTS.md`; no eliminado.
- **La roster gratuita cambia:** por eso existe el preflight. Si un slug deja de ser gratis, OpenClaw
  seguirá funcionando pero podría cobrar; el preflight lo avisa.
- **Ejecución de código:** `tecnico` está en `sandbox: off` (Koyeb no expone socket Docker). Sirve para
  *escribir* código; ejecutarlo de forma segura requeriría otra solución de sandbox.
- **Imagen oficial:** confirma el CMD/entrypoint real y las rutas de `ghcr.io/openclaw/openclaw:2026.6.1`
  con `docker inspect`, y el subcomando de `openclaw auth set`, por si difieren de lo asumido.

## Fuentes

- [OpenClaw + OpenRouter integration](https://openrouter.ai/docs/cookbook/coding-agents/openclaw-integration)
- [OpenClaw — Configuration: agents](https://docs.openclaw.ai/gateway/config-agents)
- [OpenClaw — Agent runtime](https://docs.openclaw.ai/concepts/agent) · [System prompt](https://docs.openclaw.ai/concepts/system-prompt)
- [OpenClaw — Docker install](https://docs.openclaw.ai/install/docker)
- [Deploy OpenClaw One-Click App — Koyeb](https://www.koyeb.com/deploy/openclaw)
- [OpenRouter — Models API](https://openrouter.ai/api/v1/models)
