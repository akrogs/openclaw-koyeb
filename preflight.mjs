// Preflight de modelos multi-proveedor.
// Verifica que cada modelo referenciado en openclaw.json (formato "<provider>/<modelId>")
// existe en el catalogo de su proveedor (Google, Groq o Cerebras).
//
// Politica de salida (distingue primario de fallback):
//   exit 1  -> un modelo PRIMARIO configurado no existe en su proveedor (su catalogo se
//              consulto con exito). Es un error que debe bloquear el arranque.
//   exit 0  -> todo OK; un FALLBACK que no existe solo genera AVISO (no bloquea), porque
//              algunos modelos "evaluation" (p.ej. Cerebras qwen-3-coder-480b) pueden
//              retirarse. Tambien exit 0 si falta la clave de un proveedor o falla la red.

import { readFileSync } from "node:fs";

const cfgPath = process.argv[2] || "/home/node/.openclaw/openclaw.json";

// provider -> como consultar su lista de modelos y extraer los ids.
const PROVIDERS = {
  google: {
    keyEnv: "GEMINI_API_KEY",
    url: (key) => `https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000&key=${key}`,
    headers: () => ({}),
    ids: (json) => (json.models || []).map((m) => String(m.name || "").replace(/^models\//, "")),
  },
  groq: {
    keyEnv: "GROQ_API_KEY",
    url: () => "https://api.groq.com/openai/v1/models",
    headers: (key) => ({ Authorization: `Bearer ${key}` }),
    ids: (json) => (json.data || []).map((m) => m.id),
  },
  cerebras: {
    keyEnv: "CEREBRAS_API_KEY",
    url: () => "https://api.cerebras.ai/v1/models",
    headers: (key) => ({ Authorization: `Bearer ${key}` }),
    ids: (json) => (json.data || []).map((m) => m.id),
  },
  openrouter: {
    keyEnv: "OPENROUTER_API_KEY",
    url: () => "https://openrouter.ai/api/v1/models",
    headers: (key) => ({ Authorization: `Bearer ${key}` }),
    ids: (json) => (json.data || []).map((m) => m.id),
  },
};

// Devuelve los modelos unicos con su(s) rol(es) y agente(s): { full, roles:Set, agents:Set }.
function collectModels(cfg) {
  const map = new Map();
  const addOne = (full, role, agentId) => {
    if (!full) return;
    let e = map.get(full);
    if (!e) {
      e = { full, roles: new Set(), agents: new Set() };
      map.set(full, e);
    }
    e.roles.add(role);
    if (agentId) e.agents.add(agentId);
  };
  const addModel = (m, agentId) => {
    if (!m) return;
    if (typeof m === "string") {
      addOne(m, "primary", agentId);
      return;
    }
    if (m.primary) addOne(m.primary, "primary", agentId);
    for (const f of m.fallbacks || []) addOne(f, "fallback", agentId);
  };
  for (const a of cfg?.agents?.list || []) addModel(a.model, a.id);
  addModel(cfg?.agents?.defaults?.model, "defaults");
  return [...map.values()];
}

const agentsOf = (e) => [...e.agents].join(", ") || "?";

try {
  const cfg = JSON.parse(readFileSync(cfgPath, "utf8"));

  // Agrupar por proveedor (primer segmento de "<provider>/<modelId>").
  const byProvider = {};
  for (const e of collectModels(cfg)) {
    const i = e.full.indexOf("/");
    if (i < 0) continue;
    const provider = e.full.slice(0, i);
    const modelId = e.full.slice(i + 1);
    if (!PROVIDERS[provider]) continue; // proveedor que este preflight no sabe consultar
    (byProvider[provider] ||= []).push({ ...e, provider, modelId });
  }

  if (Object.keys(byProvider).length === 0) {
    console.log("[preflight] no hay modelos de proveedores conocidos que verificar.");
    process.exit(0);
  }

  const missingPrimary = [];
  const missingFallback = [];
  let verified = 0;

  for (const [provider, models] of Object.entries(byProvider)) {
    const p = PROVIDERS[provider];
    const key = process.env[p.keyEnv];
    if (!key) {
      console.warn(`[preflight] aviso: ${p.keyEnv} no definido; se omite la verificacion de '${provider}'.`);
      continue;
    }

    let available;
    try {
      const res = await fetch(p.url(key), { headers: p.headers(key) });
      if (!res.ok) throw new Error("HTTP " + res.status);
      available = new Set(p.ids(await res.json()));
    } catch (e) {
      console.warn(`[preflight] aviso: no se pudo consultar '${provider}' (${e.message}); se omite.`);
      continue;
    }

    for (const entry of models) {
      if (available.has(entry.modelId)) {
        verified++;
      } else if (entry.roles.has("primary")) {
        missingPrimary.push(entry);
      } else {
        missingFallback.push(entry);
      }
    }
    console.log(`[preflight] ${provider}: ${models.length} modelo(s) comprobado(s).`);
  }

  // Los fallbacks que faltan solo avisan: no bloquean el arranque.
  for (const m of missingFallback) {
    console.warn(`[preflight] aviso: fallback '${m.full}' no existe en ${m.provider} (agente: ${agentsOf(m)}). Cambialo por otro modelo gratuito.`);
  }

  if (missingPrimary.length) {
    console.error("[preflight] ERROR: modelos PRIMARIOS no encontrados en su proveedor:");
    for (const m of missingPrimary) {
      console.error(`  - ${m.full}  (id '${m.modelId}' no existe en ${m.provider}; agente: ${agentsOf(m)})`);
    }
    console.error("Confirma los IDs en la consola del proveedor y actualiza openclaw.json.");
    process.exit(1);
  }

  const warn = missingFallback.length ? ` (${missingFallback.length} fallback(s) a revisar)` : "";
  console.log(`[preflight] OK: ${verified} modelo(s) verificado(s) en proveedores con clave${warn}.`);
  process.exit(0);
} catch (e) {
  console.warn(`[preflight] aviso: no se pudo ejecutar la verificacion (${e.message}); se continua.`);
  process.exit(0);
}
