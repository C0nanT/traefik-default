# 05: Workflow de deploy da borda pelo botão + Dependabot das actions

> **Difficulty:** Heavy: **suggested model:** Opus (Claude Code) / Opus or the strongest reasoning model available (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** no traefik-default, workflow disparado só por `workflow_dispatch`, recusando rodar fora da `main`, no Environment `producao`: grava chave e `known_hosts` em arquivos temporários, `ssh` com `StrictHostKeyChecking=yes` pedindo o deploy da borda (sem action de terceiros para SSH, sem checkout), depois `curl` em conantorres.dev e no domínio do bbcontainer exigindo sucesso. Dependabot da borda ganha `github-actions` (mensal, cooldown 14 dias, um grupo, sem auto-merge). `docs.sh` troca "nenhum arquivo em workflows" por "nenhum workflow de auto-merge" e confere o workflow e o Dependabot.

**Seams:**
- Seam 2: `docs.sh` do traefik-default.

**Blocked by:** 04

Status: done

- [x] Workflow só com `workflow_dispatch`; nenhum gatilho de push/PR
- [x] Recusa ref diferente de `main`
- [x] Usa Environment `producao` e os secrets nomeados no ticket 04
- [x] `ssh` direto, `StrictHostKeyChecking=yes`, chave em arquivo temporário
- [x] `curl` nos dois domínios, falha se algum não responder com sucesso
- [x] Dependabot cobre `github-actions` com mensal, `default-days: 14` e grupo
- [x] `docs.sh` barra workflow de auto-merge mas aceita o de deploy; confere os itens acima
- [ ] YAML validado localmente; smoke da borda continua passando
