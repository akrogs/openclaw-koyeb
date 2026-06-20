// Preflight de modelos multi-proveedor.
// Verifica que cada modelo referenciado en openclaw.json (formato "<provider>/<modelId>")
// existe en el catalogo de su proveedor (Google, Groq o Cerebras).
//
// Politica de salida:
//   exit 1  -> SOLO si el catalogo de un proveedor se consulto con exito y un modelId
//              configurado NO existe (error de configuracion que debe bloquear el arranque).
//   exit 0  -> todo OK, o falta la clave de un proveedor, o fallo de red (avisa y sigue).

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
};

function collectModels(cfg) {
  const ids = new Set();
  const add = (m) => {
    if (!m) return;
    if (typeof m === "string") {
      ids.add(m);
    } else {
      if (m.primary) ids.add(m.primary);
      for (const f of m.fallbacks || []) ids.add(f);
    }
  };
  for (const a of cfg?.agents?.list || []) add(a.model);
  add(cfg?.agents?.defaults?.model);
  return [...ids];
}

try {
  const cfg = JSON.parse(readFileSync(cfgPath, "utf8"));

  // Agrupar los modelos configurados por proveedor (primer segmento de "<provider>/<modelId>").
  const byProvider = {};
  for (const full of collectModels(cfg)) {
    const i = full.indexOf("/");
    if (i < 0) continue;
    const provider = full.slice(0, i);
    const modelId = full.slice(i + 1);
    if (!PROVIDERS[provider]) continue; // proveedor que este preflight no sabe consultar
    (byProvider[provider] ||= []).push({ full, modelId });
  }

  if (Object.keys(byProvider).length === 0) {
    console.log("[preflight] no hay modelos de proveedores conocidos que verificar.");
    process.exit(0);
  }

  const missing = [];
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

    for (const { full, modelId } of models) {
      if (available.has(modelId)) verified++;
      else missing.push({ provider, full, modelId });
    }
    console.log(`[preflight] ${provider}: ${models.length} modelo(s) comprobado(s).`);
  }

  if (missing.length) {
    console.error("[preflight] ERROR: modelos no encontrados en su proveedor:");
    for (const m of missing) {
      console.error(`  - ${m.full}  (id '${m.modelId}' no existe en ${m.provider})`);
    }
    console.error("Confirma los IDs en la consola del proveedor y actualiza openclaw.json.");
    process.exit(1);
  }

  console.log(`[preflight] OK: ${verified} modelo(s) verificado(s) en proveedores con clave.`);
  process.exit(0);
} catch (e) {
  console.warn(`[preflight] aviso: no se pudo ejecutar la verificacion (${e.message}); se continua.`);
  process.exit(0);
}
