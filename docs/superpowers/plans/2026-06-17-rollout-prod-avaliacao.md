# Plano de ação — fechar pendências + iniciar testes em prod (avaliação)

> Data: 2026-06-17 · Objetivo: rodar o saturno em produção (clubinho real, modo veredito) por uma janela de observação, avaliar o funcionamento real, fechar pendências e decidir go-live.

## Estado de partida (2026-06-17)
- Pipeline R1 (#0/#1/#2) validado; Fase 1 de custo (pré-filtro + caps) implementada e validada no grupo teste.
- Saturno **em produção** apontado pro clubinho real (`120363308683104573`), **modo veredito ON** (manda veredito no log + DM best-effort; NÃO cria tarefa).
- Fonte de verdade do veredito = **log do Coolify** (DM depende da janela 24h do WhatsApp).

## ⚠️ Dependência crítica: LID dos membros reais
O `_platform/lid-map.json` só tem o LID de teste do gustavo. Em grupo, o WhatsApp entrega o autor como **LID**, não telefone → `resolve_whatsapp_identity` dá null → membro real classificado como **cliente** → promessa de equipe **não detectada** (falso-negativo). Isso é o que mais ameaça a avaliação em prod. Dois caminhos (não-excludentes):
- **Manual (curto prazo):** conforme membros postam, o veredito mostra "autor LID X não resolvido"; capturar o LID, você diz quem é, mapear no `lid-map.json`. Loop até a equipe estar toda mapeada.
- **Estrutural (definitivo):** worker extrai o telefone do payload Evolution (Fase C1) → mata o lid-map manual. **Recomendado priorizar.**

## Fase A — Prontidão (hoje)
- [ ] **A1.** Confirmar deploy `qjrvrq7thogconiw7xuz94xo` healthy e 1º tick pós-deploy OK (cold-start retry cobre). Ticks firando = OK; `running:unknown` é quirk do Coolify.
- [ ] **A2.** Confirmar no log: JID prod ativo, modo veredito (env `R1_VERDICT_DM_TO=5531999594121`).
- [ ] **A3.** Montar coleta de vereditos: comando que puxa os `claude OK ... resultado:` do log do Coolify por dia (PowerShell; parse Python quebra no log). Salvar num doc de observação.

## Fase B — Observação em prod (janela ~3–5 dias úteis)
- [ ] **B1.** A cada tick ativo do clubinho, ler o veredito no log. Registrar: msgs avaliadas, autor (LID/telefone), equipe×cliente, promessa sim/não, tarefa que criaria.
- [ ] **B2.** **Mapear LIDs da equipe** (dependência crítica): capturar LIDs não-resolvidos dos vereditos → mapear no `lid-map.json` (commit + deploy). Repetir até a equipe estar coberta. (Ou esperar a Fase C1 e pular isso.)
- [ ] **B3.** Avaliar qualidade: promessas reais detectadas? equipe×cliente correto? falso-positivo (chitchat virou promessa)? falso-negativo (promessa perdida pelo pré-filtro/LID)? custo real/dia por projeto.
- [ ] **B4.** Ajustar conforme achados: regex do pré-filtro (`promise-filter.sh` + testes), lid-map, caps.

## Fase C — Fechar pendências (paralelo à observação)
- [ ] **C1. [WORKER — outro chat] Telefone do payload Evolution** (`participantPn`/`participantAlt` → `author`). **Prioridade alta** — resolve o B2 de forma estrutural. Precisa de amostra de payload de grupo real.
- [ ] **C2. [WORKER — outro chat] `identifier` no `/inbox-debug`** — fecha a parede FIFO do gate (#1b), mesmo padrão do `inbox_list_unread`. Depois, apontar `has-changes.sh` p/ `?identifier=$GID`.
- [ ] **C3. Task 5 — `--disallowedTools`** (ganho ~10-15%): ciclo medir-antes (plano `2026-06-17-custo-saturno-escala.md`, Tasks 4-5). Baixa prioridade.
- [ ] **C4. Higiene residual:** `FORCE_NO_CHANGES` dup no preview-env (inócuo, opcional limpar).

## Fase D — Critério de go-live + cutover
- [ ] **D1. Critério (definir números ao iniciar a Fase B):** ex. ≥N dias sem falso-positivo grave + ≥M promessas reais detectadas corretamente + custo/dia dentro do teto ($12 global). 
- [ ] **D2. Go-live:** limpar env `R1_VERDICT_DM_TO` + redeploy → R1 passa a **criar tarefas reais** no Bloquim do clubinho (workspace `e21deb6f-...`).
- [ ] **D3.** Observar as primeiras tarefas criadas (dedup via `search_tasks`, prazo, prioridade); ajustar.

## Ordem recomendada
A (hoje) → iniciar B em paralelo com **C1** (worker telefone, mata o gargalo de LID) → avaliar (B3) → D (go-live) quando o critério bater. C2/C3/C4 oportunistas.
