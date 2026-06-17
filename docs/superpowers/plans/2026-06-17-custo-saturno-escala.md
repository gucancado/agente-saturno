# Otimização de custo do saturno p/ escala (22 contas) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cortar o custo por tick ativo do saturno e preparar a arquitetura de custo p/ escalar a 22 projetos, sem regredir a detecção R1.

**Architecture:** Empurra trabalho pro gate barato não-LLM (pré-filtro de promessa), trima o prefixo frio do payload do Claude (`--disallowedTools`), e torna os caps de custo por-projeto. Faseado: medir baseline (Fase 0) → levers de baixo risco (Fase 1) → redesenho só se necessário (Fase 2). Itens do worker ficam marcados como coordenados (não executados aqui).

**Tech Stack:** Bash (scripts de tick/gate), YAML (`cadencia.yml`), `jq`/`yq`, `claude --print` (Haiku 4.5), Coolify API (deploy), worker MCP via curl (medição).

**Spec:** `docs/superpowers/specs/2026-06-17-custo-saturno-escala-design.md`

---

## File Structure

- `scripts/lib/promise-filter.sh` — **NOVO**. Função pura `has_promise_candidate "<texto>"` (exit 0 se casa heurístico de promessa pt-BR). Unidade testável, sem I/O.
- `scripts/lib/has-changes.sh` — **MODIFICAR**. Após detectar msg nova, sourcing de `promise-filter.sh` e só retorna "novidade" se ≥1 msg nova casa o heurístico.
- `scripts/tick-sweep.sh` — **MODIFICAR**. (a) trocar `--allowedTools` por `--disallowedTools`; (b) cap de custo por-projeto/dia.
- `scripts/cadencia.yml` — **MODIFICAR**. (a) lista `disallowed_tools`; (b) guardrails por-projeto.
- `tests/promise-filter.test.sh` — **NOVO**. Testes do regex (bash, sem DB).
- `docs/superpowers/specs/2026-06-17-custo-saturno-escala-baseline.md` — **NOVO** (Fase 0). Registra baseline + metas.

Worker (`semente-platform-worker`, **NÃO editar aqui** — coordenar no outro chat): `src/debug/routes.ts` (`identifier` em `/inbox-debug`), `src/webhook/evolution.ts` (extração de telefone do payload).

---

## Fase 0 — Medição (baseline)

### Task 1: Capturar baseline de custo do tick ativo

**Files:**
- Create: `docs/superpowers/specs/2026-06-17-custo-saturno-escala-baseline.md`

- [ ] **Step 1: Disparar 1 tick ativo controlado**

Postar uma promessa no grupo de teste (env `_whatsapp_group_jid_test` = `120363426336988804`). O JID de produção está ativo no `workspace-map.json`; p/ medir sem prod, repontar TEMP o `whatsapp_group_jid` do clubinho pro grupo de teste OU medir direto no grupo prod com uma promessa real. Decisão padrão: medir no grupo de **teste** (repont TEMP, restaurar depois).

Aguardar 1 tick ativo (≤15 min comercial). Não confundir com o 1º tick pós-deploy (cold-start).

- [ ] **Step 2: Extrair o breakdown do tick ativo dos logs do Coolify**

Run (PowerShell, parse robusto — o parse Python quebra no log do Coolify):
```
curl -s "http://5.78.199.192:8000/api/v1/applications/h5btft2bcfsz57mmmwf7do7q/logs?lines=300" -H "Authorization: Bearer <COOLIFY_TOKEN>" > /c/tmp/base.json
```
Depois, no PowerShell, achar a linha `usage:` do tick ativo e ler: `total_cost_usd` (via `sweep end ... total_cost`), `num_turns`, `cache_creation_input_tokens`, `output_tokens`, `cache_read_input_tokens`.

Expected: um objeto `usage` com os campos. Referência conhecida (2026-06-16, sweep-103): `num_turns=14`, `cost $0,112`; sweep-795 (3 msgs) `$0,223`.

- [ ] **Step 3: Registrar baseline + metas no doc**

Escrever em `2026-06-17-custo-saturno-escala-baseline.md`:
- Custo do tick ativo (mín/típico/máx observados) + composição (% cache_creation / output / cache_read).
- Projeção atual p/ 22 contas (custo_tick_ativo × ticks_ativos_estimados/dia × 22).
- **Metas numéricas:** alvo de `$/tick-ativo` (ex. −50%) e teto `$/dia` p/ 22 contas (ex. < $12/dia). Estes números saem do baseline real medido aqui.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-06-17-custo-saturno-escala-baseline.md
git commit -m "docs(custo): baseline de custo do tick ativo + metas (Fase 0)"
```

---

## Fase 1.1 — Pré-filtro de promessa no gate

### Task 2: Função pura `has_promise_candidate` (TDD)

**Files:**
- Create: `scripts/lib/promise-filter.sh`
- Test: `tests/promise-filter.test.sh`

- [ ] **Step 1: Escrever o teste falhando**

Create `tests/promise-filter.test.sh`:
```bash
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
```

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `bash tests/promise-filter.test.sh`
Expected: FAIL — `promise-filter.sh` não existe / função indefinida.

- [ ] **Step 3: Implementar `promise-filter.sh`**

Create `scripts/lib/promise-filter.sh`:
```bash
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
  # normaliza p/ minúsculas (case-insensitive sem depender de locale)
  local low; low="$(printf '%s' "$txt" | tr '[:upper:]' '[:lower:]')"
  # 1ª pessoa + verbo futuro/compromisso, ou marcadores coloquiais e de prazo.
  # ERE (grep -E). Acentos opcionais via classes.
  local re='(\bvou\b|\bvamos\b|\benvio\b|\bmando\b|\bsubo\b|\bfa[çc]o\b|\bajusto\b|\bcoloco\b|\bresolvo\b|fico respons[áa]vel|pode deixar|deixa comigo|\bj[áa] j[áa]\b|depois eu|\bamanh[ãa]\b|at[ée] (segunda|ter[çc]a|quarta|quinta|sexta|s[áa]bado|domingo|hoje|amanh[ãa]))'
  printf '%s' "$low" | grep -Eq "$re"
}
```

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `bash tests/promise-filter.test.sh`
Expected: PASS — `TODOS OK`. Se "já enviei" (fato passado) casar por engano, ajustar o regex p/ não pegar; documentar casos-limite no comentário.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/promise-filter.sh tests/promise-filter.test.sh
git commit -m "feat(gate): heurístico has_promise_candidate (pré-filtro de promessa)"
```

### Task 3: Integrar o pré-filtro no gate

**Files:**
- Modify: `scripts/lib/has-changes.sh` (após o cálculo de `LATEST`, antes do `exit 0` de novidade)

- [ ] **Step 1: Ler o estado atual do gate**

Run: `cat scripts/lib/has-changes.sh`
Confirmar o bloco que hoje decide novidade:
```bash
LATEST=$(jq -r --arg id "$GID" '[.messages[]? | select(.identifier==$id) | .created_at] | max // ""' <<<"$INBOX")
...
if [[ -z "$CURSOR" || "$LATEST" > "$CURSOR" ]]; then
  echo "has-changes[$SLUG]: novidade ($LATEST > ${CURSOR:-inicio})" >&2
  exit 0
fi
```

- [ ] **Step 2: Modificar o gate p/ exigir candidato a promessa**

Substituir o bloco de decisão de novidade por: além de `LATEST > CURSOR`, exigir que ≥1 msg nova (created_at > cursor, do grupo) tenha texto que case `has_promise_candidate`. Trecho:
```bash
# Fonte do filtro: já temos $INBOX (do /inbox-debug). Sem cursor → considerar todas.
source "$(dirname "${BASH_SOURCE[0]}")/promise-filter.sh"

if [[ -z "$CURSOR" || "$LATEST" > "$CURSOR" ]]; then
  # Há msg nova. Só dispara tick CARO se alguma msg nova do grupo for candidata
  # a promessa (pré-filtro não-LLM). Chitchat não dispara.
  CAND=0
  while IFS= read -r TXT; do
    [[ -z "$TXT" ]] && continue
    if has_promise_candidate "$TXT"; then CAND=1; break; fi
  done < <(jq -r --arg id "$GID" --arg cur "$CURSOR" \
      '.messages[]? | select(.identifier==$id) | select(($cur=="") or (.created_at > $cur)) | .message_text // empty' \
      <<<"$INBOX")

  if [[ "$CAND" == "1" ]]; then
    echo "has-changes[$SLUG]: novidade c/ candidato a promessa ($LATEST > ${CURSOR:-inicio})" >&2
    exit 0
  fi
  echo "has-changes[$SLUG]: msg nova mas sem candidato a promessa — pulando (cost-safe)" >&2
  exit 1
fi
```
NB: o campo de texto no `/inbox-debug` é `message_text` (confirmado no payload). Se o endpoint não retornar `message_text`, este lever depende do item worker (1.4) — ver Task 7.

- [ ] **Step 3: Teste manual do gate (dois casos)**

Run (com env `WORKER_URL`/`WORKER_TOKEN` setados localmente OU simulando `$INBOX`):
Caso A — grupo com promessa nova → `exit 0` + log "novidade c/ candidato".
Caso B — grupo só com chitchat novo → `exit 1` + log "sem candidato".
Expected: comportamento acima. (Validação real end-to-end no Step 5.)

- [ ] **Step 4: Commit**

```bash
git add scripts/lib/has-changes.sh
git commit -m "feat(gate): só dispara tick caro com candidato a promessa (pré-filtro)"
```

- [ ] **Step 5: Deploy + validação não-regressão**

```bash
git push origin HEAD:master
curl -s -X POST "http://5.78.199.192:8000/api/v1/deploy?uuid=h5btft2bcfsz57mmmwf7do7q" -H "Authorization: Bearer <COOLIFY_TOKEN>"
```
Postar promessa no grupo teste → confirmar nos logs que o tick ATIVA e detecta (não-regressão do pipeline R1). Postar chitchat → confirmar que o gate SKIPA ($0). Re-medir custo (Task 1, Step 2) e anotar a queda no nº de ticks ativos.

---

## Fase 1.2 — Trim do prefixo frio (`--disallowedTools`)

### Task 4: Verificar que `--disallowedTools` trima o payload

**Files:** (nenhum — experimento de medição)

- [ ] **Step 1: Adicionar disallow mínimo de teste no cadencia.yml**

Em `scripts/cadencia.yml`, perfil `sweep`, adicionar uma chave nova `disallowed_tools` com ALGUNS tools bloquim claramente não-usados (ex. `mcp__bloquim__delete_task`, `mcp__bloquim__list_plans`, `mcp__bloquim__create_workspace`). Ainda NÃO remover do código que monta args (Task 5) — aqui é só p/ medir manualmente.

- [ ] **Step 2: Rodar um tick ativo com `--disallowedTools` ad-hoc e comparar cache_creation**

Rodar localmente um `claude --print --disallowedTools "<lista>"` equivalente OU medir via tick com a flag adicionada temporariamente. Comparar `cache_creation_input_tokens` com o baseline (Task 1).
Expected: cache_creation MENOR com disallow (confirma que remove schemas do payload). Se NÃO mudar, abortar este lever e usar deny em `settings.json` (anotar no baseline doc).

- [ ] **Step 3: Commit (registro do achado)**

```bash
git add docs/superpowers/specs/2026-06-17-custo-saturno-escala-baseline.md
git commit -m "docs(custo): confirma que disallowedTools trima cache_creation"
```

### Task 5: Aplicar `--disallowedTools` no tick-sweep

**Files:**
- Modify: `scripts/cadencia.yml` (perfil `sweep`: `disallowed_tools`)
- Modify: `scripts/tick-sweep.sh` (montagem de `CLAUDE_ARGS`)

- [ ] **Step 1: Listar os tools NÃO usados pela R1 no cadencia.yml**

Em `scripts/cadencia.yml`, sob `profiles.sweep`, adicionar `disallowed_tools` com os MCP tools que a R1 NÃO usa. Usados (manter): `mcp__platform__{inbox_list_unread,inbox_mark_read,resolve_whatsapp_identity,send_whatsapp_dm}`, `mcp__bloquim__{create_task,search_tasks,list_workspace_tasks,list_workspace_members,get_task,add_task_comment,set_task_status,set_task_schedule}`, builtins `Bash/Read/Write/Edit`. Disallow (não-usados):
```yaml
    disallowed_tools:
      - mcp__bloquim__list_workspaces
      - mcp__bloquim__create_workspace
      - mcp__bloquim__add_workspace_member
      - mcp__bloquim__list_plans
      - mcp__bloquim__create_plan
      - mcp__bloquim__get_plan
      - mcp__bloquim__update_plan
      - mcp__bloquim__delete_plan
      - mcp__bloquim__search_plans
      - mcp__bloquim__attach_task_to_plan
      - mcp__bloquim__detach_task_from_plan
      - mcp__bloquim__list_task_checklist
      - mcp__bloquim__add_checklist_items
      - mcp__bloquim__update_checklist_item
      - mcp__bloquim__delete_checklist_item
      - mcp__bloquim__clear_task_checklist
      - mcp__bloquim__list_task_comments
      - mcp__bloquim__list_task_attachments
      - mcp__bloquim__add_task_attachment
      - mcp__bloquim__remove_task_attachment
      - mcp__bloquim__move_task_to_workspace
      - mcp__bloquim__update_task
      - mcp__bloquim__delete_task
      - mcp__bloquim__set_task_assignee
      - mcp__bloquim__get_task_activity
      - mcp__bloquim__list_my_tasks
      - mcp__bloquim__whoami
```

- [ ] **Step 2: Ler o trecho atual de montagem de args**

Run: `grep -n "allowed_tools\|allowedTools\|ALLOWED_TOOLS" scripts/tick-sweep.sh`
Confirmar:
```bash
ALLOWED_TOOLS=$(yq -r ".profiles.$PROFILE.allowed_tools // [] | join(\",\")" "$CADENCIA")
...
[[ -n "$ALLOWED_TOOLS" ]] && CLAUDE_ARGS+=(--allowedTools "$ALLOWED_TOOLS")
```

- [ ] **Step 3: Trocar p/ disallowedTools**

Em `scripts/tick-sweep.sh`, ler a nova chave e passar `--disallowedTools` (mantendo `--allowedTools` removido — disallow é o que corta payload):
```bash
DISALLOWED_TOOLS=$(yq -r ".profiles.$PROFILE.disallowed_tools // [] | join(\",\")" "$CADENCIA")
...
# (remover a linha do --allowedTools)
[[ -n "$DISALLOWED_TOOLS" ]] && CLAUDE_ARGS+=(--disallowedTools "$DISALLOWED_TOOLS")
```

- [ ] **Step 4: Sintaxe + deploy + validação**

Run: `bash -n scripts/tick-sweep.sh && echo OK`
Expected: `OK`.
```bash
git add scripts/cadencia.yml scripts/tick-sweep.sh
git commit -m "perf(custo): --disallowedTools trima ~24 tools bloquim não-usados do payload"
git push origin HEAD:master
curl -s -X POST "http://5.78.199.192:8000/api/v1/deploy?uuid=h5btft2bcfsz57mmmwf7do7q" -H "Authorization: Bearer <COOLIFY_TOKEN>"
```
Disparar 1 tick ativo → confirmar que a R1 ainda funciona (não removeu tool usado) e re-medir `cache_creation`/custo. Se o tick falhar por tool removido, identificar nos logs e tirar da lista.

---

## Fase 1.3 — Caps por-projeto

### Task 6: Cap de custo por-projeto/dia

**Files:**
- Modify: `scripts/cadencia.yml` (guardrails)
- Modify: `scripts/tick-sweep.sh` (guarda de custo)

- [ ] **Step 1: Adicionar guardrails por-projeto no cadencia.yml**

Em `scripts/cadencia.yml`, sob `guardrails`, adicionar (mantendo os globais como teto do agente):
```yaml
guardrails:
  cost_cap_usd_per_day: 12.00        # teto GLOBAL do agente (era 1.50; 22 contas)
  cost_cap_usd_per_project_day: 0.60 # teto por projeto/dia
  cost_cap_usd_per_tick: 0.30        # teto por invocação individual (era 0.12)
  alert_threshold_pct: 80
```

- [ ] **Step 2: Ler a guarda de custo atual**

Run: `grep -n "COST_CAP\|COST_TODAY\|COST_FILE\|OVER_DAY\|OVER_TICK" scripts/tick-sweep.sh`
Confirmar que `COST_FILE` registra linhas `{"tick_id","project","cost_usd","at"}` e que o gate diário soma `[.[].cost_usd]` do dia (global).

- [ ] **Step 3: Adicionar guarda por-projeto no loop**

Em `scripts/tick-sweep.sh`, dentro do `for SLUG`, ANTES de chamar o claude (após o gate has-changes), checar o gasto do projeto no dia:
```bash
  COST_CAP_PROJ=$(yq -r '.guardrails.cost_cap_usd_per_project_day // 0.60' "$CADENCIA")
  if [[ -f "$COST_FILE" ]]; then
    PROJ_TODAY=$(jq -s --arg p "$SLUG" '[.[] | select(.project==$p) | .cost_usd] | add // 0' "$COST_FILE")
  else
    PROJ_TODAY=0
  fi
  OVER_PROJ=$(awk -v c="$PROJ_TODAY" -v cap="$COST_CAP_PROJ" 'BEGIN { print (c >= cap) ? 1 : 0 }')
  if [[ "$OVER_PROJ" == "1" ]]; then
    log "GUARDA: projeto $SLUG estourou cap diário (\$$COST_CAP_PROJ, gasto \$$PROJ_TODAY); pulando"
    SKIPPED=$((SKIPPED+1))
    continue
  fi
```
Manter o teto global diário (`cost_cap_usd_per_day`) como hard-stop do agente.

- [ ] **Step 4: Sintaxe + deploy**

Run: `bash -n scripts/tick-sweep.sh && echo OK`
Expected: `OK`.
```bash
git add scripts/cadencia.yml scripts/tick-sweep.sh
git commit -m "feat(custo): cap de custo por-projeto/dia + teto global do agente (escala 22)"
git push origin HEAD:master
curl -s -X POST "http://5.78.199.192:8000/api/v1/deploy?uuid=h5btft2bcfsz57mmmwf7do7q" -H "Authorization: Bearer <COOLIFY_TOKEN>"
```
Validar nos logs que projeto sob o cap roda normal; (opcional) forçar `cost_cap_usd_per_project_day` baixo num teste p/ ver o GUARDA disparar.

---

## Fase 1.4 — Worker (COORDENAR no outro chat — NÃO executar aqui)

### Task 7: [WORKER] `identifier` no `/inbox-debug`

**Files (worker, não tocar neste fluxo):** `src/debug/routes.ts`

- [ ] **Coordenar:** adicionar query param `identifier` no `GET /inbox-debug` (mesmo padrão do `inbox_list_unread`, commit worker `3c9bc8a`), filtrando server-side por grupo. Sem isso, o gate (`has-changes.sh`) puxa 200 globais e msgs de grupo quieto somem atrás de grupos ativos (parede FIFO do gate, #1b). Depois de pronto no worker, atualizar `has-changes.sh` p/ passar `?identifier=$GID` em vez de filtrar client-side. Ver `NOTA-saturno-chat-2026-06-16.md` no repo do worker.

### Task 8: [WORKER] Extração de telefone do payload Evolution

**Files (worker, não tocar neste fluxo):** `src/webhook/evolution.ts`

- [ ] **Coordenar:** em `parseEvolutionPayload`, preferir o telefone real (`key.participantPn`/`participantAlt`) sobre o LID (`key.participant`) ao gravar `author`. Requer amostra de payload de grupo real (worker não persiste raw hoje — instrumentar temporariamente OU capturar live). Quando pronto, o `_platform/lid-map.json` manual do saturno fica obsoleto (remover numa limpeza posterior).

---

## Fase 2 — Redesenho (SÓ se Fase 1 não bater a meta da Fase 0)

### Task 9: Avaliar necessidade (gate de decisão)

- [ ] **Step 1: Comparar custo pós-Fase-1 com a meta**

Re-medir `$/tick-ativo` e projeção `$/dia` p/ 22 (mesmo método da Task 1) após Tasks 2–6. Comparar com a meta do baseline.
Expected: decisão registrada — "meta atingida, parar" OU "abrir Fase 2".

- [ ] **Step 2: Se abrir Fase 2 — escrever spec própria**

Fase 2 (MCP fino ~3 tools + colapsar loop agêntico + paralelismo do sweep) é um redesenho com superfície grande → merece **spec própria** (novo ciclo brainstorming → writing-plans). NÃO detalhar aqui. Registrar a decisão e os números que a justificam.

---

## Self-Review (preenchido)

**Spec coverage:** Fase 0 → Task 1. Fase 1.1 (pré-filtro) → Tasks 2–3. Fase 1.2 (trim) → Tasks 4–5. Fase 1.3 (caps) → Task 6. Fase 1.4 (worker) → Tasks 7–8 (coordenados). Fase 2 → Task 9 (gate). Error handling: fail-closed no gate (Task 3 Step 2), reverter disallow (Task 5 Step 4), GUARDA por-projeto (Task 6 Step 3). Testing: regex unit (Task 2), não-regressão (Tasks 3/5 Step 5). Métrica: Task 1 Step 3 + Task 9.

**Placeholders:** nenhum `<COOLIFY_TOKEN>` é o token do CLAUDE.md global (não inline aqui por higiene). Listas de tools e regex são concretos.

**Type/nome consistency:** `has_promise_candidate` usado igual em promise-filter.sh, has-changes.sh e nos testes. `disallowed_tools` (yaml) → `DISALLOWED_TOOLS` (bash) → `--disallowedTools`. `cost_cap_usd_per_project_day` (yaml) → `COST_CAP_PROJ` (bash). `message_text` é o campo do payload do inbox-debug.

**Dependência cruzada:** Task 3 assume `message_text` no `/inbox-debug` (já presente); o filtro server-side (`?identifier`) é melhoria do worker (Task 7), não bloqueia o pré-filtro client-side.
