#!/bin/bash
# has-changes.sh <slug> — gate de mudanca barato (NAO-LLM).
#   exit 0 = ha novidade desde o ultimo sweep  -> rodar o agente (caro)
#   exit 1 = sem novidade                        -> pular projeto (economiza)
#
# FONTE (Fase 2): mensagens novas no grupo do projeto (inbox do worker),
# comparadas a um cursor por projeto em projetos/<slug>/memoria/.sweep-cursor
# (timestamp ISO do ultimo sweep). O cursor e avancado pelo tick-sweep.sh apos
# um sweep bem-sucedido.
#
# Override de teste: FORCE_NO_CHANGES=1 -> sempre "sem novidade" (freio global).
set -uo pipefail

SLUG="${1:?usage: has-changes.sh <slug>}"
WORKSPACE="${WORKSPACE:-/workspace}"

# Freio global de seguranca (env): pula tudo.
if [[ "${FORCE_NO_CHANGES:-0}" == "1" ]]; then
  echo "has-changes[$SLUG]: FORCE_NO_CHANGES — sem novidade" >&2
  exit 1
fi

MAP="$WORKSPACE/_platform/workspace-map.json"
JID=$(jq -r --arg s "$SLUG" '.workspaces[]? | select(.slug==$s) | .whatsapp_group_jid // empty' "$MAP" 2>/dev/null)
if [[ -z "$JID" || "$JID" == "null" ]]; then
  # Sem grupo mapeado: nao ha o que varrer por enquanto (evita tick caro a toa).
  echo "has-changes[$SLUG]: sem whatsapp_group_jid no map — nada a varrer" >&2
  exit 1
fi

# Inbox do worker representa o grupo como identifier "+<digitos>" (sem @g.us).
DIGITS=$(echo "$JID" | sed 's/@.*//' | tr -cd '0-9')
GID="+$DIGITS"

: "${WORKER_URL:?WORKER_URL nao definida}"
: "${WORKER_TOKEN:?WORKER_TOKEN nao definida}"

INBOX=$(curl -fsS --max-time 10 -H "X-Agent-Token: ${WORKER_TOKEN}" \
  "${WORKER_URL}/inbox-debug?limit=200" 2>/dev/null)
if [[ -z "$INBOX" ]]; then
  # Fail-closed: erro de inbox -> pula (cost-safe). Proximo tick tenta de novo.
  echo "has-changes[$SLUG]: erro buscando inbox — pulando (cost-safe)" >&2
  exit 1
fi

LATEST=$(jq -r --arg id "$GID" '[.messages[]? | select(.identifier==$id) | .created_at] | max // ""' <<<"$INBOX")
if [[ -z "$LATEST" || "$LATEST" == "null" ]]; then
  echo "has-changes[$SLUG]: sem mensagens do grupo na inbox — sem novidade" >&2
  exit 1
fi

CURSOR_FILE="$WORKSPACE/projetos/$SLUG/memoria/.sweep-cursor"
CURSOR=$(cat "$CURSOR_FILE" 2>/dev/null || echo "")

# Comparacao lexicografica de ISO-8601 = ordem cronologica.
if [[ -z "$CURSOR" || "$LATEST" > "$CURSOR" ]]; then
  echo "has-changes[$SLUG]: novidade ($LATEST > ${CURSOR:-inicio})" >&2
  exit 0
fi

echo "has-changes[$SLUG]: sem novidade (cursor=$CURSOR)" >&2
exit 1
