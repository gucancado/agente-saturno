#!/bin/bash
# ledger.sh — ledger de DEDUP por projeto (Fase 2).
#
# Registra "regra X já disparou pro alvo Y" pra não repetir alerta/cobrança a
# cada tick. JSONL append-only em projetos/<slug>/memoria/_ledger.jsonl —
# persiste entre ticks via git (tick-sweep faz pull no início + commit/push no
# fim). Volume baixo + 1 sweep por vez (flock) → JSONL simples basta.
#
# Cada linha: {"ts","rule","key","meta"}. `key` = identidade do disparo
# (ex.: sha1(autor+objeto) numa promessa; "YYYY-MM-DD" num digest diário).
#
# Uso (bash):
#   source scripts/lib/ledger.sh
#   if ledger_seen <slug> <rule> <key>; then echo "já registrado"; fi
#   ledger_add <slug> <rule> <key> '<meta_json>'
#
# O AGENTE (claude --print), que só tem `jq` liberado (não `bash`), opera o
# mesmo arquivo direto via jq — ver "padrão jq" no fim deste arquivo e nas
# skills de regra.
set -uo pipefail
WORKSPACE="${WORKSPACE:-/workspace}"

_ledger_file() { echo "$WORKSPACE/projetos/$1/memoria/_ledger.jsonl"; }

# ledger_seen <slug> <rule> <key> -> exit 0 se JÁ registrado, 1 se novo.
ledger_seen() {
  local f; f="$(_ledger_file "$1")"
  [[ -f "$f" ]] || return 1
  local hit
  hit=$(jq -c --arg r "$2" --arg k "$3" 'select(.rule==$r and .key==$k)' "$f" 2>/dev/null | head -1)
  [[ -n "$hit" ]]
}

# ledger_add <slug> <rule> <key> [meta_json]
ledger_add() {
  local f; f="$(_ledger_file "$1")"
  mkdir -p "$(dirname "$f")"
  local meta="${4:-{}}"
  jq -nc --arg ts "$(date -u +%FT%TZ)" --arg r "$2" --arg k "$3" --argjson m "$meta" \
    '{ts:$ts, rule:$r, key:$k, meta:$m}' >> "$f"
}

# ── Padrão jq pro agente (sem bash) ─────────────────────────────────────────
# Checar (vazio = novo; não-vazio = já feito):
#   jq -c --arg r "<rule>" --arg k "<key>" 'select(.rule==$r and .key==$k)' \
#     projetos/<slug>/memoria/_ledger.jsonl 2>/dev/null | head -1
# Registrar:
#   jq -nc --arg ts "<iso>" --arg r "<rule>" --arg k "<key>" --argjson m '<meta>' \
#     '{ts:$ts,rule:$r,key:$k,meta:$m}' >> projetos/<slug>/memoria/_ledger.jsonl
