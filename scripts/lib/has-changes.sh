#!/bin/bash
# has-changes.sh <slug> — gate de mudanca barato (NAO-LLM).
#   exit 0 = ha novidade desde o ultimo sweep  -> rodar o agente (caro)
#   exit 1 = sem novidade                        -> pular projeto (economiza)
#
# FASE 0: STUB. Sempre devolve "ha mudanca" (exit 0), exceto se
# FORCE_NO_CHANGES=1 (pra exercitar o caminho de skip em teste).
#
# FASE 2 plugara as fontes reais (spec §10 "Gate de mudanca"):
#   - cursor de mensagens novas em `messages` (worker)
#   - tarefas com updated_at recente (Bloquim)
#   - alerta novo em meta_alerts (Supabase)
#   - transcricao nova (Fireflies)
# O cursor "ultimo sweep visto" por projeto vivera no worker (junto do ledger).
set -uo pipefail

SLUG="${1:?usage: has-changes.sh <slug>}"

if [[ "${FORCE_NO_CHANGES:-0}" == "1" ]]; then
  echo "has-changes[$SLUG]: stub FORCE_NO_CHANGES — sem novidade" >&2
  exit 1
fi

echo "has-changes[$SLUG]: stub Fase 0 — assumindo novidade" >&2
exit 0
