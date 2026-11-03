# 02: Peça `limite-taxa` por visitante real

> **Difficulty:** Heavy: **suggested model:** Opus (Claude Code) / Opus or the strongest reasoning model available (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** um site plugado que pede `limite-taxa@file` limita cada visitante a uma média de 5 req/s, com rajada de 100 e período de 1 s. Acima disso, o visitante recebe 429. O visitante é o IP mais à direita do `X-Forwarded-For` que não seja da Cloudflare (`ipStrategy.excludedIPs` com as mesmas faixas). Quando a conexão não vem da Cloudflare, o cabeçalho é descartado na entrada, e o limite conta pelo IP da conexão. Um `X-Forwarded-For` forjado não abre um balde novo. A peça sai do mesmo arquivo gerado na partida que a `so-cloudflare` e usa a mesma lista. O README e o guia de integração passam a citá-la.

Lembrete da spec: não commitar `.scratch/borda-cloudflare/`. Adicione só os arquivos que você mudou, e use mensagens de commit neutras.

**Seams:**
- Smoke test da borda (`testes/smoke.sh` + arquivo novo em `testes/verificacoes/`)
- `testes/docs.sh`

**Blocked by:** 01 (peça `so-cloudflare` gerada na partida)

Status: ready-for-human

- [x] Um site de teste novo no `sites-extras.yml`, com `limite-taxa@file`, responde 429 no smoke depois de uma rajada acima de 100 requisições
- [x] Variar o `X-Forwarded-For` forjado a cada requisição não evita o 429
- [x] Toda espera ou rajada do teste tem limite e falha com mensagem clara (`CODING_STANDARDS.md`)
- [x] A peça aparece na API do painel com média 5, rajada 100 e `excludedIPs` igual à lista do `trustedIPs`
- [x] O whoami, sem a peça, não recebe 429 depois da mesma rajada
- [x] O README e o guia de integração citam `limite-taxa@file`, e o `testes/docs.sh` confere isso
- [x] `testes/docs.sh`, `testes/deploy.sh` e `testes/smoke.sh` passam
- [x] Nenhum commit inclui `.scratch/`
