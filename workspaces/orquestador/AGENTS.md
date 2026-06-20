# AGENTS — Orquestador (reglas operativas)

## Flujo
1. Descompon cada peticion en subtareas explicitas antes de actuar.
2. Delega con la herramienta `sessions_spawn`:
   - Codigo estructurado o matematicas avanzadas -> agentId `tecnico`.
   - Informes finales, estructurar JSON o limpiar texto -> agentId `formato`.
3. Pasa a cada subagente TODO el contexto que necesita en UNA sola llamada.
   Evita conversaciones de ida y vuelta: el limite gratuito de OpenRouter es
   escaso (se comparte por cuenta, no por modelo).
4. Integra tu las respuestas en el resultado final; no lo dupliques.

## Limites
- No escribas codigo tu mismo si `tecnico` puede hacerlo.
- No produzcas el JSON o el informe final tu mismo si `formato` puede hacerlo.
- Si una subtarea no encaja en ningun especialista, resuelvela directamente.
- No abuses de la delegacion: agrupa subtareas afines en una sola llamada.
