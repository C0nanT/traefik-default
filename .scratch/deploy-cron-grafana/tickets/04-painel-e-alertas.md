# 04: Painel "Deploy (cron)" e alertas no homelab

> **Difficulty:** Standard: **suggested model:** Sonnet (Claude Code) / Sonnet (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** no repositório **homelab-monitoring**, o painel Logs ganha a linha "Deploy (cron)": estado por site (ok/falhou), horário da última rodada e logs com o rótulo do cron. Dois alertas provisionados no mesmo arquivo dos outros, com o modelo de mensagem existente e limites em `limites`: "Deploy falhou (VPS)" (`deploy_falhou == 1`, sem espera, cita o `app`, se resolve ao voltar a 0) e "Cron de deploy parado" (última rodada há mais de 30 min, ou série ausente). README do homelab descreve a linha e os alertas; `docs.sh` confere.

**Seams:**
- Seam 3: smoke do homelab (painel e alertas provisionados).

**Blocked by:** 02, 03

Status: ready-for-agent

- [ ] Linha "Deploy (cron)" com os três painéis no painel Logs
- [ ] Alerta "Deploy falhou (VPS)" sem espera, com o `app` na mensagem
- [ ] Alerta "Cron de deploy parado" (30 min ou série ausente)
- [ ] Limites no lugar de sempre; mensagem no modelo existente
- [ ] Smoke do homelab e `docs.sh` passam
