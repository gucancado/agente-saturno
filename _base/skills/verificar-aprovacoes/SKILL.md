---
name: verificar-aprovacoes
description: Passo 0 do tick. Varre tarefas-filhas com tag type:aprovacao, identifica decisões nos comentários (validando autoria), atualiza _platform/approval-cache.json. Não executa ações aqui — apenas marca decisões para uso posterior.
---

# verificar-aprovacoes

Skill que processa o backlog de pedidos de aprovação acumulado entre ticks. Roda como passo 0, antes de qualquer outra coisa.

## Algoritmo

1. Carregar `_platform/approvers.yml` em memória.

2. Para cada workspace do agente (de `_platform/workspace-map.json`):
   - `bloquim:search_tasks` com filtro `tag: type:aprovacao, status: pending`.

3. Para cada tarefa-filha pendente:
   - `bloquim:list_task_comments(filha_id)` — pega cronologia.
   - Para cada comentário (do mais recente ao mais antigo):
     - Validar `author.email` contra `approvers.yml`.
     - Se autor não-aprovador: skipar; postar 1x em `<agente>-monitoramento` `"Tentativa de aprovação por usuário não-autorizado: <email> em #<filha_id>"`. NÃO comentar na filha (não dar feedback ao falso aprovador).
     - Se autor aprovador: parsear texto:
       - `regex /\b(\[APROVADO\]|aprovado)\b/i` (palavra isolada): decisão = `approved`
       - `regex /\b(\[NEGADO\]|negado|\[CANCELAR\]|cancelar)\b/i`: decisão = `denied`
       - Demais: ignora (comentário comum).
     - Aceitar primeira decisão encontrada (mais recente vence).

4. Recuperar `hash` da descrição da filha (linha `hash: <h>`).

5. **Aprovado/Negado encontrado**:
   - Atualizar `_platform/approval-cache.json` adicionando entry:
     ```json
     {
       "hash": "<h>",
       "decision": "approved" | "denied",
       "by": "<author.email>",
       "at": "<comment.created_at>",
       "filha_task_id": "<id>",
       "consumed_at": null
     }
     ```
   - NÃO executar a ação aqui. Execução acontece quando agente, durante processamento da pai, invocar `aprovacao-humana` para a mesma ação (hash bate; encontra entry; executa; marca `consumed_at`).

6. **Sem decisão E filha pendente há ≥ 24h**:
   - Comentar na pai (`parent`): `"Aprovação pendente há 24h. Estou replanejando ou pausando essa tarefa."`
   - Marcar filha: `bloquim:set_task_status(filha_id, done)` + `bloquim:add_tag(filha_id, expired)`.
   - Marcar pai: `bloquim:add_tag(parent, replanejar)`.

7. Persistir `_platform/approval-cache.json`. Commit + push acontecem ao final do tick (job do tick.sh, não desta skill).

## Não invente decisões

Comentários ambíguos (`"aprovado em parte"`, `"sim mas..."`) NÃO são aprovações. Só palavras isoladas exatas. Em dúvida, ignore o comentário e deixe pendente — owner vai esclarecer ou reescrever.

## Performance

Limite: processar até 50 filhas pendentes por tick. Se houver mais, processa as 50 mais antigas e loga o excesso. Não deveria acontecer em operação normal.
