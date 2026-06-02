---
name: responder-whatsapp
description: Responde mensagem do WhatsApp em thread existente ou inicia nova. Sempre invoca aprovacao-humana primeiro para classificar L1/L2. Usa MCP whatsapp (aiteks-evolution) para envio efetivo.
---

# responder-whatsapp

Skill para enviar mensagem WhatsApp via Evolution API.

## Quando usar

Quando processar tarefa com tag `canal:whatsapp` e decidir responder.

## Como usar

### Entrada

- `to`: número E.164 do destinatário (ex: `+5531999998888`)
- `message`: texto da resposta
- `mode`: `"reply"` (resposta em thread existente) ou `"new_thread"` (mensagem inicial)
- `thread_context`: histórico relevante (extraído da descrição da tarefa)
- `parent_task_id`: ID da tarefa Bloquim que motivou o envio

### Algoritmo

1. **Confirmar contato conhecido**:
   - `platform:lookup_contact(agent: <nome>, channel: whatsapp, identifier: <to>)`
   - Se retorna route: `to_contact: known`. Senão: `to_contact: unknown` (precisa de classificação ou aprovação).

2. **Gating via aprovacao-humana**:
   - `aprovacao-humana.classify(action: "whatsapp.send", params: { to, mode, to_contact, template_match }, parent_task_id)`
   - Se retorna `executed`: enviar mensagem (passo 3).
   - Se retorna `pending`: parar; tarefa-filha de aprovação foi criada.
   - Se retorna `denied`: parar; replanejar (registrar em memória que ação foi negada).

3. **Enviar via MCP**:
   - `whatsapp:send_message(instance: <env EVOLUTION_INSTANCE>, to: <to>, message: <message>)`

4. **Registrar em memória**:
   - `memoria/relacionamento/<identifier-sanitizado>.md` — atualiza nota do contato (data, conteúdo enviado, contexto).
   - `memoria/log-de-execucoes/<data>-task_<id>.md` — entry de execução.

5. **Atualizar tarefa-pai no Bloquim**:
   - Se mensagem encerra o atendimento: `bloquim:set_task_status(parent, done)` + comentário `[CONCLUÍDO TICK_<id>] <resumo>`.
   - Se aguarda resposta: status `in_progress` + comentário com resumo.

## Template matching (para reduzir aprovações L2)

Existe um conjunto de templates aprovados (`_base/templates/whatsapp/`). Se a mensagem casa exatamente com um template (ou é uma renderização canônica de um template com variáveis preenchidas), `template_match: true` permite que ações em thread nova entrem em L1 ao invés de L2.

Templates iniciais (a criar conforme demanda):
- `qualificacao-lead-clinica.md` — primeiro contato com lead de clínica
- `confirmacao-agendamento.md` — confirmação de horário
- `lembrete-consulta.md` — lembrete 24h antes
- `disclosure-agente.md` — texto padrão de disclosure (sempre inclui na 1ª mensagem)

## Disclosure obrigatório

Toda mensagem em nova thread (`mode: new_thread`) DEVE incluir disclosure de que é agente automatizado, com fallback humano. Não negociável — política pública da BeeAds.
