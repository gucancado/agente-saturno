#!/bin/bash
# promise-filter.sh — heurístico NÃO-LLM de "candidato a promessa" (pt-BR).
# Alta cobertura (recall), baixa precisão de propósito: o LLM faz a precisão no
# tick. Objetivo: o gate só dispara o tick caro quando alguém parece prometer
# algo, evitando custo com chitchat. fail-closed: sem casar → não é candidato.
#
# Uso: has_promise_candidate "<texto>"  → exit 0 (candidato) | 1 (não).

has_promise_candidate() {
  local txt="${1:-}"
  [[ -z "$txt" ]] && return 1
  # minúsculas (ASCII; acentos tratados via classes + locale UTF-8 no grep)
  local low; low="$(printf '%s' "$txt" | tr '[:upper:]' '[:lower:]')"
  # LC_ALL=C.UTF-8: faz o grep tratar á/ã/ç/é como CHAR (não bytes), senão as
  # classes [áa] etc. quebram em locale C. C.utf8 existe no Debian do container.
  # Fato passado explícito ("já enviei/fiz/subi...") NÃO é promessa → exclui antes.
  if printf '%s' "$low" | LC_ALL=C.UTF-8 grep -Eq '\bj[áa] (enviei|mandei|fiz|subi|ajustei|coloquei|resolvi)\b'; then
    return 1
  fi
  # 1ª pessoa + verbo futuro/compromisso, ou marcadores coloquiais e de prazo.
  # "vamos" (solto) foi deixado de fora de propósito: ruidoso em chitchat
  # ("vamos ver/lá"); promessas no plural costumam ter verbo de ação ou prazo.
  local re='(\bvou\b|\benvio\b|\bmando\b|\bsubo\b|\bfa[çc]o\b|\bajusto\b|\bcoloco\b|\bresolvo\b|fico respons[áa]vel|pode deixar|deixa comigo|\bj[áa] j[áa]\b|depois eu|\bamanh[ãa]\b|at[ée] (segunda|ter[çc]a|quarta|quinta|sexta|s[áa]bado|domingo|hoje|amanh[ãa]))'
  printf '%s' "$low" | LC_ALL=C.UTF-8 grep -Eq "$re"
}
