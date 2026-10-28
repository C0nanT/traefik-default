# 02: O cron publica `deploy_falhou` e o horário da rodada

> **Difficulty:** Standard: **suggested model:** Sonnet (Claude Code) / Sonnet (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** a cada rodada, o script do cron grava no volume `textfile` da borda (o mesmo do `loki_dados_bytes`) um `.prom` com `deploy_falhou{app="<pasta>"}` (0/1 por site) e um gauge com o horário Unix do fim da rodada. Gravação atômica (temporário no mesmo diretório + rename). O diretório vem do Docker (mountpoint do volume real da borda) ou de variável de ambiente (usada nos testes). Falha ao gravar a métrica vira linha no log e não muda o deploy. O node exporter passa a publicar as séries. README: seção do cron explica a métrica e que, a cada mudança no script, é preciso reinstalá-lo em `/usr/local/bin`.

**Seams:**
- Seam 1: teste local do cron.
- Seam 2: smoke da borda (node exporter publica `deploy_falhou`).

**Blocked by:** 01

Status: ready-for-human

- [x] Todos ok → 0 por site + horário; um falhando → 1 só para ele e linha `ERRO` no log
- [x] Gravação atômica: sem temporário sobrando, arquivo final válido
- [x] Falha ao gravar a métrica não altera o deploy
- [x] Sem variáveis de teste, caminhos de produção
- [x] Smoke da borda confere `deploy_falhou` no node exporter
- [x] README explica a métrica e a reinstalação do script
