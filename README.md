# agente-template

Template para repositórios de agentes da plataforma Semente. Clonar para criar um novo agente.

Ver `c:\Users\gusta\Projetos\agente-semente\SPEC.md` (spec da plataforma, v0.3.1+).

## Como criar um agente novo

1. `gh repo create gucancado/agente-<nome> --private --template gucancado/agente-template`
2. `git clone gh:gucancado/agente-<nome>`
3. Preencher `_platform/identity-map.md` com identidades reais.
4. Editar `CLAUDE.md` (raiz) — persona, voz, propósito do agente.
5. Editar `_base/CLAUDE.md` — regras compartilhadas entre projetos.
6. Adicionar projetos em `projetos/<slug>/` copiando de `_template/`. Atualizar `_platform/workspace-map.json` com cada novo.
7. Definir cadência em `scripts/cadencia.yml`.
8. Configurar env vars no Coolify (ver `secrets/.env.example`).
9. Push → auto-deploy (ver `.github/workflows/deploy.yml`).

## Estrutura

```
.
├── CLAUDE.md                    # persona + regras globais (dir pai do cwd dos ticks)
├── _platform/                   # consumido pelo entrypoint do container
├── _base/                       # contexto + skills compartilhados entre projetos
├── projetos/                    # um diretório por workspace Bloquim atendido
│   ├── _template/               # copiar para criar novo projeto
│   ├── _sistema/                # workspace meta (tarefa-mãe de monitoramento)
│   └── <slug>/                  # projeto real
├── scripts/                     # tick.sh, cadencia.yml, libs
├── docker/                      # Dockerfile + entrypoint
└── secrets/                     # gitignored; env vars vivem no Coolify
```

## Modos de runtime

O agente roda via supercronic; cada perfil em `scripts/cadencia.yml` aponta pro script via campo `runner`:

- **task-driven** (`runner: tick.sh`, default) — work-list = fila de tarefas Bloquim. Prompt: `tick-prompt.md`.
- **sweep** (`runner: tick-sweep.sh`) — work-list = projetos de `_platform/workspace-map.json`. Cada projeto passa por um gate de mudança barato (`scripts/lib/has-changes.sh`) antes do `claude --print`. Prompt: `tick-sweep-prompt.md`. Usado por agentes auditores (ex.: saturno).

Ambos são agênticos (`claude --print` + MCPs + aprovação `aprovacao-humana`). Um agente tipicamente habilita só um perfil.

Detalhe sobre cada arquivo na SPEC §6 da plataforma.
