# Identidade do agente

> Substituir todos os `<placeholders>` ao instanciar o template.

## Identidade externa

| Recurso | Valor |
|---|---|
| Nome do agente | `<NOME>` |
| Função | `<SDR / gestor de tráfego / analista / ...>` |
| Conta Google | `<nome>@beeads.com.br` (Workspace) ou `<nome>@gmail.com` |
| WhatsApp | +55 31 9XXXX-XXXX |
| Bloquim user | mesmo email da conta Google |
| GitHub PAT | env var `<NOME_UPPER>_GITHUB_TOKEN` (Coolify) |
| Anthropic workspace | `beeads-<nome>` |
| Evolution instance | `<nome>` |
| Worker token | env var `<NOME_UPPER>_WORKER_TOKEN` (Coolify) |

## Cadência

Perfis ativos: `<responsive | daily | batch | urgent_only>` (configuração em `scripts/cadencia.yml`).

## Owner e governança

- Owner: Gustavo Cançado de Azevedo (`gucancado`)
- Provisionado em: `<YYYY-MM-DD>`
- Política de aprovação: `_base/policies/approval.yml`
- Approvers: `_platform/approvers.yml`

## Workspaces atendidos

Lista canônica em `_platform/workspace-map.json`. Esta seção é informativa apenas.

## Histórico

- `<YYYY-MM-DD>`: provisionamento inicial
