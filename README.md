# OpenClaw en Koyeb — 3 agentes con modelos gratuitos de OpenRouter

Despliegue reproducible de [OpenClaw](https://docs.openclaw.ai) en [Koyeb](https://www.koyeb.com)
con tres agentes especializados que enrutan a modelos **gratuitos** de OpenRouter.

## Arquitectura de agentes

| Agente | Rol | Modelo (free) |
|---|---|---|
| `orquestador` (default) | Agente principal: divide el problema en subtareas, gestiona el contexto masivo y delega. | **Nemotron 3 Ultra** — `openrouter/nvidia/nemotron-3-ultra-550b-a55b:free` |
| `tecnico` | Tareas técnicas aisladas: código estructurado y matemáticas avanzadas. | **Qwen 2.5 72B** — `openrouter/qwen/qwen-2.5-72b-instruct:free` |
| `formato` | Informes finales, estructurar JSON y limpiar texto. | **Llama 3.3 70B** — `openrouter/meta-llama/llama-3.3-70b-instruct:free` |

```
        Web Control UI (Koyeb :18789)
                  │
            ┌─────▼──────┐
            │ orquestador│  Nemotron 3 Ultra (thinking=high)
            └──┬──────┬──┘
   sessions_spawn│      │sessions_spawn
        ┌────────▼┐   ┌─▼────────┐
        │ tecnico │   │ formato  │
        │ Qwen2.5 │   │ Llama3.3 │
        └─────────┘   └──────────┘
```

La delegación usa `subagents.allowAgents` + `sessions_spawn` (agente-a-agente nativo de OpenClaw).
Cada modelo tiene un **fallback gratuito** para resistir los errores 429 del tier gratuito.

> La inferencia LLM corre en OpenRouter, **no** en Koyeb. El contenedor solo ejecuta el gateway
> (proceso ligero de I/O): basta una instancia pequeña (~0.5–1 GB RAM), sin GPU.

## Estructura

```
openclaw-koyeb/
├── Dockerfile        # parte de ghcr.io/openclaw/openclaw:latest + hornea la config
├── entrypoint.sh     # siembra openclaw.json en el volumen sin borrar auth/dispositivos
├── openclaw.json     # config declarativa de los 3 agentes
├── .env.example      # plantilla de secretos
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
5. **Instancia:** la más pequeña disponible (eco/nano, ~512 MB).
6. **Puerto:** expón **`18789`** como puerto público. Health checks HTTP: `/healthz` (liveness) y
   `/readyz` (readiness).
7. **Secrets (variables de entorno):**
   - `OPENROUTER_API_KEY`
   - `OPENCLAW_GATEWAY_TOKEN`
8. **Volumen persistente:** crea un **Koyeb Volume** montado en **`/home/node/.openclaw`** para que las
   aprobaciones de dispositivo y los perfiles de auth sobrevivan a redeploys. El `entrypoint.sh` solo
   reescribe `openclaw.json` y respeta el resto. ⚠️ Un volumen ata el servicio a una sola instancia.
9. **Despliega** y espera a que `/readyz` devuelva 200.
10. **Aprueba el dispositivo** (paso obligatorio post-deploy):
    - Abre `https://<service>.koyeb.app/overview`.
    - Introduce el `OPENCLAW_GATEWAY_TOKEN` y pulsa **Connect**.
    - En Koyeb → pestaña **Console** del servicio → ejecuta el comando que aprueba el dispositivo pendiente.
11. **(Si hace falta) registra el auth de OpenRouter** dentro del contenedor (queda en el volumen):
    ```sh
    openclaw auth set openrouter:default --key "$OPENROUTER_API_KEY"
    ```
    En muchos casos basta con la env `OPENROUTER_API_KEY` ya inyectada — verifícalo con la prueba de abajo.

## Verificación

- `curl https://<service>.koyeb.app/healthz` y `/readyz` → 200.
- La Web UI carga, el token conecta y el dispositivo queda aprobado.
- En la Console: `openclaw agents list` muestra `orquestador`, `tecnico`, `formato` con sus modelos.
- **Prueba de orquestación** (chat con `orquestador` en la Web UI):
  > "Calcula la serie de Fibonacci hasta n=20 en Python y entrégame un informe final en JSON con el código y los resultados."

  Esperado: el `orquestador` delega la generación de código a `tecnico` (Qwen) y la redacción del JSON
  final a `formato` (Llama), visible en las trazas de subagentes.

## Caveats

- **Slugs `:free`:** la roster gratuita de OpenRouter cambia con frecuencia. Verifica los slugs exactos en
  https://openrouter.ai/models antes de desplegar (sobre todo el de Nemotron 3 Ultra).
- **Rate limits gratuitos:** ~50 req/día sin crédito (≈1000/día con $10) y pocos req/min. Un orquestador
  que abre subagentes consume varias llamadas por petición → bajo uso real es probable toparse con 429.
  Mitigado con fallbacks y `maxPingPongTurns`, no eliminado.
- **Ejecución de código:** `tecnico` está en `sandbox: off` (Koyeb no expone socket Docker). Sirve para
  *escribir* código; ejecutarlo de forma segura requeriría otra solución de sandbox.
- **Imagen oficial:** confirma el CMD/entrypoint real y las rutas de `ghcr.io/openclaw/openclaw:latest`
  con `docker inspect` por si difieren de lo asumido en el `Dockerfile`/`entrypoint.sh`.

## Fuentes

- [OpenClaw + OpenRouter integration](https://openrouter.ai/docs/cookbook/coding-agents/openclaw-integration)
- [OpenClaw — Configuration: agents](https://docs.openclaw.ai/gateway/config-agents)
- [OpenClaw — Docker install](https://docs.openclaw.ai/install/docker)
- [Deploy OpenClaw One-Click App — Koyeb](https://www.koyeb.com/deploy/openclaw)
- [OpenRouter — Free models](https://openrouter.ai/collections/free-models)
