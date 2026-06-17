# Baseline de custo do tick ativo — saturno (Fase 0)

> Data: 2026-06-17 · Fonte: medições reais do grupo de teste com o código atual (2026-06-16), via log de `usage` (commit `49861df`). Modelo: Haiku 4.5 (in $1/MTok, out $5/MTok, cache-write $1,25/MTok, cache-read $0,10/MTok).

## Medições do tick ATIVO (grupo de teste, código atual pré-otimização)

| Tick | Custo | num_turns | cache_creation (tok) | output (tok) | cache_read (tok) | nº msgs |
|---|---|---|---|---|---|---|
| sweep-107 | $0,098 | ~10 | — | — | — | 2 |
| sweep-286 | $0,101 | — | — | — | — | 2 |
| sweep-103 | $0,112 | 14 | 32.713 | 6.713 | 371.175 | 3 |
| sweep-266 | $0,175 | 17 | 27.941 | 8.351 | 500.309 | 3 |
| sweep-795 | $0,223 | ~14 | — | — | — | 3 |

**Tick ativo: $0,10–0,22 (mediana ~$0,14). Tick skip: $0,00.**

## Composição (sweep-103, $0,112 — representativo)

| Componente | tok | custo | % |
|---|---|---|---|
| cache_creation (prefixo frio: schemas MCP + system + ctx, escrito 1×/tick) | 32.713 | $0,0409 | ~37% |
| cache_read (prefixo relido a cada turn) | 371.175 | $0,0371 | ~33% |
| output (Haiku $5/MTok) | 6.713 | $0,0336 | ~30% |
| input uncached | ~tiny | ~$0 | ~0% |

**Leitura:** prefixo frio (cache_creation) + cache_read = **~70%** do custo → atacáveis por (a) trimar o prefixo (`--disallowedTools`, Fase 1.2) e (b) reduzir turns (menos releitura). Output (~30%) cai com menos turns/verbosidade.

## Projeção atual p/ 22 contas (SEM otimização)

Hoje **todo** msg-novo no grupo dispara tick ativo (gate só checa novidade, não promessa). Custo/dia ≈ `nº_ticks_ativos/dia × $0,14 × nº_projetos_ativos`. Driver de escala = **nº de ticks ativos**, dominado por volume de mensagens, não por promessas. Em 22 contas tagarelas → ordem de **$7–16/dia (~$200–500/mês)** (estimativa do design). O cap diário global de $1,50 estoura cedo e mata projetos.

## Metas (pós-Fase 1)

1. **Reduzir nº de ticks ativos** (maior lever de escala): pré-filtro de promessa (Fase 1.1) → só dispara tick quando há candidato a promessa, não em chitchat. Alvo: cortar ≥60% dos ticks ativos em grupo tagarela.
2. **Reduzir $/tick-ativo**: `--disallowedTools` (Fase 1.2) ataca os ~37% de cache_creation (remover ~24 schemas bloquim não-usados). Alvo: −20–30% no cache_creation → ~−10–15% no tick.
3. **Teto de custo sustentável p/ 22 contas**: caps por-projeto (Fase 1.3) — `cost_cap_usd_per_project_day` $0,60 + teto global do agente $12/dia. **Meta de operação: < $12/dia p/ 22 contas.**

## Como re-medir (validação pós-lever)

Repetir a leitura do `usage:` no log do Coolify após cada lever, no grupo de teste, comparando `cache_creation_input_tokens`, `output_tokens`, `num_turns` e `total_cost_usd` com esta tabela. Atribuir o ganho de cada lever isoladamente.
