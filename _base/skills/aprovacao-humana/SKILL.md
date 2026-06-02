---
name: aprovacao-humana
description: Classifica ação em L0/L1/L2 conforme _base/policies/approval.yml. Para L2, gerencia tarefa-filha de aprovação no Bloquim, checa cache de aprovações consumíveis (_platform/approval-cache.json) e decide se executa ou cria pedido.
---

# aprovacao-humana

Skill central do gating de ações do agente. Invocada antes de QUALQUER ação externa.

## Quando usar

Sempre que você for executar uma ação que tenha efeito fora do agente:

- Enviar mensagem WhatsApp ou email
- Criar/atualizar/deletar tarefa de OUTRO usuário no Bloquim
- Modificar conta de cliente (Meta Ads, Google Ads, CRM)
- Eliminar ou exportar dados de cliente
- Criar evento de calendário com participantes externos

Para ações exclusivamente internas (escrever memória, atualizar suas próprias tarefas, git push em seu próprio repo), você NÃO precisa invocar esta skill — são L0.

## Como usar

### Entrada

Especifique:
- `action`: string que case com uma `action:` em `_base/policies/approval.yml` (ex: `whatsapp.send`)
- `params`: objeto JSON com os parâmetros da ação. Inclua tudo que afeta o efeito real (ex: destinatário, conteúdo, ID alvo)
- `parent_task_id`: ID da tarefa-pai no Bloquim que motivou a ação

### Algoritmo

1. **Classificar**: consulta `_base/policies/approval.yml`, encontra regra que case com `action` e `when:`. Default = L2.

2. **L0**: executa direto. Loga em `memoria/log-de-execucoes/<data>-<task_id>.md`.

3. **L1**: executa direto. Loga em `memoria/log-de-execucoes/`. Posta comentário `[L1] <descrição da ação>` na tarefa-pai.

4. **L2**: computa `hash = SHA1(action + canonical_json(params))`. Consulta `_platform/approval-cache.json`:

   - **Aprovado, não consumido**: executa ação real; marca `consumed_at`; comenta na tarefa-filha `[EXECUTADO <ts>]`; retorna `executed`.
   - **Negado/Cancelado**: comenta na tarefa-pai `[NEGADO L2] <ação> recusada. Replanejando.`; retorna `denied`.
   - **Não existe**: cria tarefa-filha de aprovação (esquema abaixo); retorna `pending`. NÃO executa.
   - **Pending** (filha já existe, sem decisão): retorna `pending`. NÃO duplica pedido.

### Esquema da tarefa-filha L2

```yaml
title: "[APROVAÇÃO] <descrição curta>"
description: |
  hash: <h>
  ação: <action>
  params: <JSON formatado>
  conteúdo: |
    ---
    <texto exato, se aplicável>
    ---
  origem: tarefa #<parent_task_id>
  tick: <TICK_ID>
tag: type:aprovacao
assignee: <email do owner — primeiro de approvers.yml com is_owner: true>
parent: <parent_task_id>
status: pending
```

### Status da tarefa-pai

NÃO MUDE em função da aprovação. Pai progride pela lógica de trabalho. Aprovação é metadata externa.

## Critério de "to_contact: known"

Conhecido se `platform:lookup_contact(channel, identifier)` retorna route. Senão, unknown.

## Implementação sugerida

- Bash + `jq` + `yq` + `sha1sum`.
- Bibliotecas auxiliares em `scripts/lib/` chamadas via Bash.
- Para cálculo de hash: `printf '%s%s' "$action" "$(jq -cS . <<<"$params")" | sha1sum | awk '{print $1}'`

## Outputs esperados

Retorne sempre um dos:
- `executed` — ação executada (L0/L1, ou L2 com aprovação cacheada)
- `pending` — pedido criado ou já em espera
- `denied` — recusada
