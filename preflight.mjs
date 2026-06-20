// Preflight de modelos OpenRouter.
// Verifica que cada modelo referenciado en openclaw.json existe en el catalogo
// de OpenRouter y es gratuito.
//
// Politica de salida:
//   exit 1  -> SOLO si el catalogo se consulto con exito y un slug configurado
//              NO existe (error de configuracion que debe bloquear el arranque).
//   exit 0  -> todo OK, o fallo de red/imprevisto (no bloquea: se avisa y sigue).
//
// Un modelo que existe pero dejo de ser gratuito produce un AVISO, no un fallo.

import { readFileSync } from "node:fs";

const cfgPath = process.argv[2] || "/home/node/.openclaw/openclaw.json";
const CATALOG_URL = "https://openrouter.ai/api/v1/models";

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

const stripPrefix = (id) => id.replace(/^openrouter\//, "");
const isFree = (p = {}) =>
  (p.prompt === "0" || p.prompt === 0) && (p.completion === "0" || p.completion === 0);

try {
  const cfg = JSON.parse(readFileSync(cfgPath, "utf8"));
  const configured = collectModels(cfg).filter((id) => id.startsWith("openrouter/"));

  if (configured.length === 0) {
    console.log("[preflight] no hay modelos openrouter/ que verificar.");
    process.exit(0);
  }

  let catalog;
  try {
    const res = await fetch(CATALOG_URL);
    if (!res.ok) throw new Error("HTTP " + res.status);
    catalog = await res.json();
  } catch (e) {
    console.warn(`[preflight] aviso: no se pudo consultar OpenRouter (${e.message}); se omite la verificacion.`);
    process.exit(0);
  }

  const available = new Map((catalog?.data || []).map((m) => [m.id, m]));
  const missing = [];
  const notFree = [];

  for (const full of configured) {
    const slug = stripPrefix(full);
    const m = available.get(slug);
    if (!m) {
      missing.push(slug);
    } else if (!isFree(m.pricing)) {
      notFree.push(slug);
    }
  }

  for (const s of notFree) {
    console.warn(`[preflight] aviso: '${s}' ya NO es gratuito (precio > 0).`);
  }

  if (missing.length) {
    console.error("[preflight] ERROR: slugs no encontrados en OpenRouter:");
    for (const s of missing) console.error("  - " + s);
    console.error("Revisa los IDs en https://openrouter.ai/models y actualiza openclaw.json.");
    process.exit(1);
  }

  console.log(`[preflight] OK: ${configured.length} modelos verificados.`);
  process.exit(0);
} catch (e) {
  console.warn(`[preflight] aviso: no se pudo ejecutar la verificacion (${e.message}); se continua.`);
  process.exit(0);
}
