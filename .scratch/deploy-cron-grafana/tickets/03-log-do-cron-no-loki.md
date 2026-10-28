# 03: O log do cron chega ao Loki

> **Difficulty:** Standard: **suggested model:** Sonnet (Claude Code) / Sonnet (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** o Alloy da borda monta o log do cron só leitura e envia as linhas ao Loki com rótulo próprio (ex.: `job="atualizar-apps"`), continuando a ler depois do logrotate. O formato do log não muda. README da seção de logs cita o rótulo e uma consulta de exemplo.

**Seams:**
- Seam 2: smoke da borda (linha escrita no log do cron aparece no Loki com o rótulo).

**Blocked by:** 01

Status: ready-for-agent

- [ ] Alloy lê o log do cron, só leitura, com rótulo próprio
- [ ] Leitura sobrevive à rotação do log
- [ ] Smoke da borda confere a linha no Loki com o rótulo
- [ ] README cita o rótulo e uma consulta LogQL
