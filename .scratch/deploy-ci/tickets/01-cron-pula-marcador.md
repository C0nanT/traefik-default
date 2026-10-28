# 01: O cron pula os sites marcados com `.deploy-pelo-ci`, e nasce o teste local de deploy

> **Difficulty:** Standard: **suggested model:** Sonnet (Claude Code) / Sonnet (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** o script do cron deixa de atualizar a pasta de site que tem o arquivo-marcador `.deploy-pelo-ci`; as outras continuam como hoje (bbcontainer segue no cron). Para isso ser testável sem VPS, o script passa a aceitar raiz das pastas e caminho da trava por variáveis de ambiente (padrão = valores de produção de hoje), e nasce o teste local novo da Seam 1: `docker` de mentira no PATH, pastas temporárias, saída `ok`/`FALHA` no estilo de `testes/lib.sh`. Esse teste é a base que os tickets 02 e 03 estendem.

**Seams:**
- Seam 1: teste novo do script de deploy e do cron (aqui só a parte do cron).

**Blocked by:** None (can start immediately)

Status: ready-for-human

- [x] Pasta com `.deploy-pelo-ci` é pulada: nenhum `pull`/`up` chamado nela
- [x] Pasta sem marcador continua recebendo `pull` + `up -d`, como hoje
- [x] Sem as variáveis de ambiente novas, o script usa exatamente os caminhos de produção de hoje (`/opt/apps`, trava atual)
- [x] Teste novo roda sem VPS, sem rede e sem as portas do smoke, sai com código ≠ 0 se alguma verificação falhar
- [x] README da borda cita o marcador na parte do cron
