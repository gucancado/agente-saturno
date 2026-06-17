#!/bin/bash
# Testa has_promise_candidate: exit 0 = candidato a promessa, exit 1 = não.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib" && pwd)"
source "$DIR/promise-filter.sh"

fail=0
assert() { # <esperado 0|1> <texto> <descricao>
  local exp="$1" txt="$2" desc="$3"
  if has_promise_candidate "$txt"; then got=0; else got=1; fi
  if [[ "$got" != "$exp" ]]; then echo "FAIL: $desc (esperado $exp, got $got) :: '$txt'"; fail=1
  else echo "ok: $desc"; fi
}

# Promessas de equipe (esperado 0 = candidato)
assert 0 "subo a campanha amanhã" "promessa: subo amanhã"
assert 0 "vou ajustar o público hoje" "promessa: vou ajustar hoje"
assert 0 "envio o relatório até sexta" "promessa: envio até sexta"
assert 0 "pode deixar comigo, faço isso já já" "promessa: deixa comigo"
assert 0 "fico responsável pelo criativo" "promessa: fico responsável"

# Não-promessas (esperado 1 = não candidato)
assert 1 "oi-vamos-testar-aqui" "saudação/teste"
assert 1 "bom dia, tudo certo?" "saudação"
assert 1 "já enviei o relatório ontem" "fato passado"
assert 1 "qual o prazo da campanha?" "pergunta"
assert 1 "" "vazio"

[[ "$fail" == "0" ]] && echo "TODOS OK" || { echo "HOUVE FALHAS"; exit 1; }
