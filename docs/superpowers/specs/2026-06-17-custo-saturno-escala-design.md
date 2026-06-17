# Design — Otimização de custo do saturno para escala (22 contas)

> Data: 2026-06-17 · Status: aprovado (brainstorming) · Próximo: writing-plans
> Repo: `agente-saturno` (itens do worker `semente-platform-worker` marcados como coordenados, não editados aqui)

## Problema

Hoje o saturno (1 instância, perfil `sweep`, Haiku 4.5) audita o projeto clubinho. Cada tick é uma chamada `claude --print`. Custo medido (2026-06-16): tick **skip = $0** (gate não-LLM não vê msg nova → não chama o Claude); tick **ativo = $0,10–0,22** (média ~$0,14). Drivers do tick ativo:

1. **Prefixo frio** (cache_creation, ~$0,015–0,02/tick) — schemas dos ~49 MCP tools (bloquim ~30 + platform) + system + contexto, escritos 1× por tick (processo frio, sem cache cross-tick). Pago por **(projeto × tick ativo)**.
2. **Output** (Haiku $5/MTok) — por msg avaliada × turns.
3. **cache_read** — prefixo relido a cada turn.

Projeção naive p/ **22 contas**: 1 projeto tagarela ≈ $0,30–0,75/dia → 22 ≈ **$7–16/dia (~$200–500/mês)**. Além disso, o **cap diário ($1,50) é global** → em 22 contas estoura cedo e mata a maioria dos projetos. A arquitetura atual de custo/caps **não escala**.

**Achado-chave:** reduzir a frequência do cron NÃO baixa o custo (skips já são $0; o trabalho é proporcional a msgs novas processadas, não a nº de ticks). O custo é dominado por (a) prefixo frio por tick ativo e (b) turns por msg avaliada.

## Meta

- Cortar `$/tick-ativo` (alvo numérico definido na Fase 0 a partir do baseline real).
- Projeção de custo p/ 22 contas dentro de um teto (definir na Fase 0; referência de trabalho: < $10–15/dia).
- **Não-regressão:** pipeline R1 (#0/#1/#2, já validado em 2026-06-16 — sweep-103) segue detectando promessa de equipe corretamente.

## Escopo

- **Incluído:** custo + preparação de escala p/ 22 contas, **faseado**.
- **Worker:** itens listados e marcados `WORKER — coordenar com o outro chat`; NÃO editados neste fluxo (worker está sendo editado em paralelo).
- **Fora:** go-live (limpar `R1_VERDICT_DM_TO`) — decisão separada do owner; itens de robustez não-custo já tratados (cold-start retry, git-ops gateados).

## Arquitetura geral

1 instância varre os 22 projetos por sweep; o gate deixa projeto ocioso de graça (só ativos custam). Fluxo do tick com as melhorias:

```
cron → has-changes.sh [novidade? + candidato-promessa? + filtro identifier server-side]
     → SIM: claude --print (prefixo trimado) avalia só msgs candidatas
            → veredito no log (+DM best-effort) → custo registrado por projeto → cap por-projeto
     → NÃO: skip ($0)
```

Princípio: empurrar trabalho pro **gate barato não-LLM** e minimizar o que o Claude vê. Cada lever é medida isoladamente (Fase 0 → baseline).

## Fase 0 — Medição (baseline)

Pré-requisito de tudo: sem baseline não dá pra afirmar ganho.

- Reaproveita o log de `usage` já existente (`tick-sweep.sh`, commit `49861df`).
- Rodar **1 tick ativo controlado** (postar msg-promessa no grupo de teste `_whatsapp_group_jid_test`) e capturar do `CLAUDE_OUT`: `total_cost_usd`, `num_turns`, e breakdown `cache_creation_input_tokens` / `output_tokens` / `cache_read_input_tokens`.
- Registrar baseline (custo + composição do tick ativo atual) em `docs/superpowers/specs/` ou memória.
- Definir as metas numéricas: `$/tick-ativo` alvo e projeção `$/dia` p/ 22 contas.
- Repetir a medição depois de cada lever (1.1, 1.2) p/ atribuir o ganho real.

## Fase 1 — Levers (saturno)

### 1.1 Pré-filtro de promessa no gate (maior lever de escala)

- **Onde:** `scripts/lib/has-changes.sh` (gate não-LLM). Hoje retorna exit 0 (roda tick caro) se `LATEST > cursor`.
- **Mudança:** além de "há msg nova?", aplicar um **regex de candidato a promessa** sobre o `message_text` das msgs novas do grupo. Só retorna exit 0 se houver ≥1 msg nova do grupo do projeto que case o heurístico.
- **Heurístico (alta cobertura, pt-BR):** 1ª pessoa + verbo futuro/compromisso. Conjunto inicial: `\b(vou|vamos|envio|mando|subo|fa[çc]o|ajusto|coloco|resolvo|fico respons[áa]vel|pode deixar|deixa (comigo)?|j[áa] j[áa]|depois eu|amanh[ãa]|at[ée] (segunda|ter[çc]a|quarta|quinta|sexta|hoje|amanh[ãa]))\b` (case-insensitive, sem acento-sensível). Recall alto, precisão baixa de propósito — o LLM faz a precisão no tick.
- **Efeito:** grupos tagarelas só disparam tick caro quando alguém de fato promete algo → corta drasticamente ticks ativos em escala.
- **Risco/mitigação:** falso-negativo (promessa fora do padrão não dispara). Mitiga com regex amplo + revisão periódica dos padrões (alimentada pelo digest/observação). Documentar explicitamente o trade-off custo×recall. Decisão: **fail-closed** (sem candidato → skip) — perder uma promessa rara é aceitável vs custo em escala; padrões ampliam-se com o uso.
- **Detalhe de cursor:** o gate continua usando `LATEST vs cursor`; se há msg nova mas sem candidato, o tick não roda e o cursor (avançado só por tick-sweep em sucesso) não avança → próximas chamadas do gate re-rodam o regex sobre as mesmas msgs (barato, não-LLM). Aceitável.

### 1.2 Trim do prefixo frio (`--disallowedTools`)

- **Onde:** `scripts/tick-sweep.sh` (monta `CLAUDE_ARGS`) + `scripts/cadencia.yml` (lista de tools).
- **Mudança:** o `--allowedTools` atual **não** reduz o payload (só gateia execução; os ~49 schemas continuam no contexto). Trocar por **`--disallowedTools`** listando explicitamente os tools NÃO usados pela R1 (os ~24 bloquim extras + tools platform não usados), OU deny em `settings.json`.
- **Verificação (Fase 0):** confirmar que `--disallowedTools` de fato remove do payload (medir cache_creation antes/depois). Se não cortar, escalar pro deny em settings.json.
- **Risco/mitigação:** remover um tool que a regra usa → tick falha. Mitiga: começar removendo só os claramente não-usados, medir, validar 1 tick ativo. Reverter a lista se quebrar.

### 1.3 Caps por-projeto

- **Onde:** `scripts/tick-sweep.sh` (lógica de guard) + `scripts/cadencia.yml` (guardrails).
- **Hoje:** `cost_cap_usd_per_tick` compara o `TOTAL_COST` acumulado do sweep (global); `cost_cap_usd_per_day` é global.
- **Mudança:** orçamento **por-projeto** — cap diário por projeto (ex. $0,50/projeto/dia) + um teto global do agente (ex. ~$11/dia p/ 22). O cost-file já registra `"project":"$SLUG"` por linha → somar por (projeto, dia) p/ o gate.
- **Efeito:** um grupo barulhento não consome o orçamento dos outros 21.

## Fase 1 — Worker (coordenado, NÃO editar aqui)

Marcados `WORKER — coordenar com o outro chat`:

- **`identifier` no `GET /inbox-debug`** → `has-changes.sh` filtra server-side. Hoje puxa 200 globais e filtra client-side → msgs de grupo quieto somem quando grupos ativos enchem a janela de 200 ("parede FIFO do gate", #1b). Mesmo padrão já aplicado ao `inbox_list_unread` (commit worker `3c9bc8a`).
- **Extração de telefone do payload Evolution** (`participantPn`/`participantAlt` em `src/webhook/evolution.ts`) → gravar em `author` → mata o `_platform/lid-map.json` manual; identidade resolve automático p/ todos os membros. Precisa de **amostra de payload real de grupo** p/ confirmar o nome do campo (worker não persiste raw hoje).

## Fase 2 — Redesenho (só se Fase 1 não bater a meta)

- **MCP fino:** server dedicado com ~3 tools p/ R1 (ex. `list_group_unread`, `resolve_identity`, `emit_verdict_or_task`) em vez de bloquim+platform inteiros → prefixo frio mínimo. Maior lever (~85%) mas maior trabalho.
- **Colapsar loop agêntico:** 1 tool devolve msgs + identidade resolvida de uma vez → agente faz 1 passe de classificação → menos turns/output.
- **Paralelismo do sweep:** se o wall-time de varrer 22 (ticks ativos sequenciais) incomodar.

## Error handling

- Inbox/worker falha no gate → **fail-closed** (skip, cost-safe), como hoje.
- Pré-filtro sem candidato → skip (fail-closed, ver 1.1).
- `--disallowedTools` removeu tool usado → tick falha (error visível) → reverter lista.
- Cap por-projeto atingido → skip do projeto + log; demais projetos seguem.

## Testing

- **Regex do pré-filtro:** testes unitários (promessa de equipe → pega; chitchat/saudação → não pega; fala de cliente → não dispara). Casos reais: as 3 msgs do grupo teste (4927 saudação=não, 4928 cobrança-a-terceiro=não, 5159 "subo a campanha amanhã"=sim).
- **Medição antes/depois** por lever (harness da Fase 0).
- **Não-regressão:** validar 1 tick ativo após cada mudança — o pipeline #0/#1/#2 (sweep-103) deve continuar detectando a promessa e classificando EQUIPE.

## Métrica de sucesso

- `$/tick-ativo` reduzido em X% (X definido na Fase 0 com baseline).
- Projeção `$/dia` p/ 22 contas dentro do teto definido.
- R1 segue detectando promessa de equipe (não-regressão) e respeitando modo veredito.

## Notas / referências

- Custo e drivers: memória `saturno-custo-tick`. Pipeline validado: `saturno-inbox-backlog` (sweep-103, 2026-06-16). Estado operacional: `saturno-estado-operacional`.
- Não tocar `_platform/`, `_base/policies/`, `scripts/` durante um tick (regra do agente); este é trabalho humano/PR, fora de tick.
