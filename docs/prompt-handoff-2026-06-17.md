Continuação do agente-saturno (auditor/sweep da BeeAds). cwd = c:/Users/gusta/Projetos/agente-saturno. Idioma pt-BR. Convenção: escolha recomendada-vs-alternativa → ir de recomendada sem perguntar.

LEIA PRIMEIRO (nesta ordem):
- docs/handoff-2026-06-17.md (estado completo, faltantes, infra — auto-contido)
- Memórias do projeto: saturno-grupos-catalogo, saturno-inbox-backlog, saturno-custo-tick, saturno-estado-operacional, saturno-bug-traps-deploy
- Specs/planos: docs/superpowers/specs/2026-06-17-custo-saturno-escala-design.md (+ -baseline.md); docs/superpowers/plans/2026-06-17-{custo-saturno-escala,rollout-prod-avaliacao}.md

ESTADO (tudo em master; branch local feat/r1-verdict-mode; ~22 commits deployados):
- Saturno VIVO em prod, modo veredito ON (env R1_VERDICT_DM_TO=5531999594121), Haiku, cron sweep.
- 4 projetos monitorados (workspace-map.json): clubinho-da-historia, cbv-clinica, tagless-brasil, bluma-cf. Todos modo veredito (veredito vai pro LOG do Coolify = fonte de verdade; DM best-effort).
- VALIDADO ao vivo: R1 ponta-a-ponta (sweep-103: LID→tel, promessa detectada); pré-filtro de promessa (sweep-107 roda / sweep-362 chitchat skip $0); sweep de 4 projetos (sweep-105: 4 projetos, CBV ativou e produziu veredito OK).
- Fase 1 de custo entregue: pré-filtro de promessa no gate (scripts/lib/promise-filter.sh + has-changes.sh) + caps por-projeto (cadencia.yml: project_day $0,60, global $12, tick $0,30). Fix do JID legado (hífen) no matching.

O QUE FALTA (prioridade):
1. 🔴 GARGALO — LID dos membros REAIS: _platform/lid-map.json só tem o LID de teste do gustavo. Nos 4 grupos de prod os membros chegam como LID não-mapeado → R1 classifica "cliente" → promessa de equipe NÃO detectada → vereditos vazios. Solução estrutural = worker extrair telefone do payload Evolution (participantPn/participantAlt em src/webhook/evolution.ts) — é o item C1, no CHAT DO WORKER (semente-platform-worker, sendo editado em paralelo; ver NOTA-saturno-chat-2026-06-16.md lá). Alternativa: mapear LIDs na mão conforme aparecem nos vereditos.
2. Worker (outro chat): C1 telefone do payload + C2 identifier no /inbox-debug (fecha parede FIFO do gate) + registrar Bluma CF no catálogo (GET /admin/agents/saturno/groups já existe).
3. Task 5 --disallowedTools (~10% custo, deferido; medir trim antes; NÃO remover --allowedTools às cegas).
4. Go-live: limpar env R1_VERDICT_DM_TO + redeploy → R1 cria tarefas reais no Bloquim.

INFRA (sem SSH — chave rejeitada; tudo via API):
- Coolify API http://5.78.199.192:8000/api/v1, token no ~/.claude/CLAUDE.md global. uuids: saturno h5btft2bcfsz57mmmwf7do7q, worker qlp2n4fi3jlklisftet1y7cz. Deploy POST /deploy?uuid=. Logs GET /applications/<uuid>/logs?lines=N — PARSEAR COM POWERSHELL (parse Python quebra). Envs GET .../envs (real_value).
- Worker via curl: X-Agent-Token=WORKER_TOKEN do env saturno; POST /mcp (JSON-RPC SSE); GET /inbox-debug?limit=200 (max 200). Catálogo de grupos: GET /admin/agents/saturno/groups com X-Owner-Token=OWNER_ADMIN_TOKEN do env worker.
- jq NÃO existe no Git Bash local → PowerShell. c:/tmp p/ temp.
- Coletor de vereditos: scripts/ops/collect-verdicts.ps1 ($env:COOLIFY_TOKEN=...).
- Kill-switch: FORCE_NO_CHANGES=1 + redeploy. Bug-traps: 1º tick pós-deploy pode cold-startar (retry 30s cobre); running:unknown = quirk Coolify; .git não persiste no /workspace (cursor reseta no redeploy); DM só entrega na janela 24h.

PRÓXIMO PASSO: decidir o gargalo do LID (item 1 — priorizar C1 no chat do worker, recomendado), seguir a observação em prod (plano rollout) até bater critério → go-live. Começa lendo docs/handoff-2026-06-17.md e confirma o estado antes de agir.
