#!/bin/bash
# identidades.sh — cache de associação telefone→identidade por projeto.
# Espelha o padrão do ledger.sh. JSONL em projetos/<slug>/memoria/_identidades.jsonl.
# Linha: {"phone","class","userId","name","source","confidence","evidence","ts"}.
# class: equipe | cliente | hipotese_equipe. phone = só dígitos (canônico).
# O AGENTE opera via jq direto (allowlist, SEM head/tail); este script é dev-only.
set -uo pipefail
WORKSPACE="${WORKSPACE:-/workspace}"
_id_file() { echo "$WORKSPACE/projetos/$1/memoria/_identidades.jsonl"; }

# id_lookup <slug> <phone_digits> -> imprime a última linha do telefone (ou vazio).
id_lookup() {
  local f; f="$(_id_file "$1")"
  cat "$f" 2>/dev/null | jq -s --arg p "$2" 'map(select(.phone==$p)) | last // empty'
}

# id_put <slug> <phone> <class> <userId|null> <name> <source> <confidence> <evidence>
id_put() {
  local f; f="$(_id_file "$1")"; mkdir -p "$(dirname "$f")"
  jq -nc --arg p "$2" --arg c "$3" --arg u "$4" --arg n "$5" \
        --arg s "$6" --arg cf "$7" --arg e "$8" \
    '{phone:$p,class:$c,userId:(if $u=="null" then null else $u end),name:$n,source:$s,confidence:$cf,evidence:$e,ts:(now|todate)}' \
    >> "$f"
}
# Padrão jq pro AGENTE (sem este script, sem head/tail):
#   lookup: cat projetos/<slug>/memoria/_identidades.jsonl 2>/dev/null | jq -s --arg p "<digitos>" 'map(select(.phone==$p)) | last // empty'
#   put:    jq -nc --arg p ... '{phone:$p,...,ts:(now|todate)}' >> projetos/<slug>/memoria/_identidades.jsonl
