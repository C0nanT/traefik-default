# 03: Script de deploy da borda (`traefik`)

> **Difficulty:** Standard: **suggested model:** Sonnet (Claude Code) / Sonnet (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** o caminho `traefik` do `deploy-vps`: recusa se o git de `/opt/traefik` tiver mudança local (`.env` e `acme/` são ignorados pelo git), imprime o commit atual, `git pull --ff-only`, imprime o commit novo, `up -d`, espera Traefik, Loki e Alloy de pé (até 2 min). SHA não se aplica (vai até a ponta da `main`). Sem rollback.

**Seams:**
- Seam 1: teste novo do script de deploy e do cron (com `git` de mentira).

**Blocked by:** 02 (Script de deploy de um site…)

Status: ready-for-human

- [x] Mudança local no git → recusa sem `pull` nem `up`
- [x] `pull` que não é fast-forward → falha sem `up`
- [x] Log mostra commit de antes e de depois
- [x] Traefik, Loki ou Alloy não ficando de pé no prazo → falha com mensagem
- [x] Caminho feliz → código 0
- [x] Casos acima cobertos pelo teste local
