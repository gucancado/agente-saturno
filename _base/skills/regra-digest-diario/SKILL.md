---
name: regra-digest-diario
description: REGRA DE AUDITORIA (R14). Uma vez por dia, monta um resumo do projeto (pendências, promessas em aberto, SLAs estourados, saldo) e envia ao owner via número B. Visão proativa de saúde sem ruído. STATUS: RASCUNHO — revisar horário/conteúdo; depende de envio via B (template, fora da janela 24h).
---

# R14 — Digest diário ao owner (via B)

> **RASCUNHO pra revisão.** ⚙️ CONFIGURAR antes de ativar. **Depende** de envio via B — e, como é proativo (1x/dia, provavelmente fora da janela 24h), exige **template Cloud aprovado** na Meta.

## Condição

É o **primeiro sweep do dia após o horário do digest** (e ainda não enviado hoje).

⚙️ CONFIGURAR:
- Horário do digest (ex.: 08:30 America/Sao_Paulo).
- Conteúdo/seções do resumo.
- Owner destinatário (telefone p/ B).

## Ação

**Aviso ao owner via B** (`whatsapp.send`) com resumo do projeto:
- pendências (tarefas Bloquim abertas/atrasadas),
- promessas em aberto (criadas por R1, ainda não concluídas),
- SLAs estourados (cliente aguardando há > X),
- saldo Meta (se baixo).

Classificação: aviso proativo fora da janela 24h → **template** (L1 se `template_match`, senão L2). Dentro da janela → texto livre L1.

⚠️ **PRÉ-REQUISITOS:**
- Envio via **B** implementado (`/send-cloud`).
- **Template Cloud** "digest" aprovado na Meta (texto proativo fora de 24h). Sem ele, este digest só sai se o owner tiver dado DM no B nas últimas 24h.

Tudo via `aprovacao-humana`. Saturno **nunca** posta no grupo nem envia via A.

## Dedup (ledger)

Chave: `(projeto, "digest", YYYY-MM-DD)`. Um por dia por projeto.

## Fonte

Bloquim (tarefas), ledger (promessas/SLAs), `meta_alerts`/`meta-mcp` (saldo). Agrega tudo num texto curto.

## Saída esperada

`executed` (digest enviado) / `pending` (template em L2) / skip (já enviado hoje). Log em `memoria/log-de-execucoes/`.
