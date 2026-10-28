# 03: Script de deploy da borda (`traefik`)

> **Difficulty:** Standard: **suggested model:** Sonnet (Claude Code) / Sonnet (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** o caminho `traefik` do `deploy-vps`: recusa se o git de `/opt/traefik` tiver mudança local (`.env` e `acme/` são ignorados pelo git), imprime o commit atual, `git pull --ff-only`, imprime o commit novo, `up -d`, espera Traefik, Loki e Alloy de pé (até 2 min). SHA não se aplica (vai até a ponta da `main`). Sem rollback.

**Seams:**
- Seam 1: teste novo do script de deploy e do cron (com `git` de mentira).

**Blocked by:** 02 (Script de deploy de um site…)

Status: ready-for-agent

- [ ] Mudança local no git → recusa sem `pull` nem `up`
- [ ] `pull` que não é fast-forward → falha sem `up`
- [ ] Log mostra commit de antes e de depois
- [ ] Traefik, Loki ou Alloy não ficando de pé no prazo → falha com mensagem
- [ ] Caminho feliz → código 0
- [ ] Casos acima cobertos pelo teste local
