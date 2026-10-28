# 05: Checklist manual da falha forçada

> **Difficulty:** Light: **suggested model:** Haiku (Claude Code) / claude-4.5-haiku-thinking (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** checklist manual no README da borda (e referência no do homelab): reinstalar o script do cron na VPS e subir a borda com o Alloy novo; ver as séries e as linhas no painel; forçar uma falha (ex.: `IMAGE_TAG` com tag inexistente no `.env` de um site, temporário) e receber "Deploy falhou (VPS)" no Telegram; desfazer e ver o alerta se resolver; conferir que o cron parado dispara (opcional: desligar o cron por 30+ min).

**Seams:**
- Seam 2/3 indiretamente via `docs.sh` (checklist presente).

**Blocked by:** 04

Status: ready-for-human

- [x] Checklist no README da borda com todos os passos, e referência no homelab
- [x] `docs.sh` confere o checklist
