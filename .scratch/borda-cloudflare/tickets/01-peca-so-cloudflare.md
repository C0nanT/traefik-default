# 01: Peça `so-cloudflare` gerada na partida

> **Difficulty:** Heavy: **suggested model:** Opus (Claude Code) / Opus or the strongest reasoning model available (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** um site plugado que pede `so-cloudflare@file` nas labels só aceita conexões cujo IP de origem esteja nas faixas da Cloudflare. Qualquer outra conexão recebe 403. A peça é gerada pelo script de partida do Traefik, a partir da mesma lista do `trustedIPs` do `traefik.yml`, e fica no diretório `gerado/`, ao lado do roteador do painel. Se a lista sair vazia, o script escreve um AVISO no stderr e a peça aceita só `127.0.0.1/32`: fecha os sites que a usam, sem abrir para todos, e o Traefik sobe normalmente. Sites que não pedem a peça (o whoami, o bbcontainer) não mudam. O README e o guia de integração passam a citar a peça no contrato, com o aviso de que ela é só para sites com nuvem laranja.

Lembrete da spec: não commitar `.scratch/borda-cloudflare/`. Adicione só os arquivos que você mudou, e use mensagens de commit neutras.

**Seams:**
- Smoke test da borda (`testes/smoke.sh` + arquivo novo em `testes/verificacoes/`)
- `testes/docs.sh`

**Blocked by:** None (can start immediately)

Status: ready-for-human

- [x] Um site de teste novo no `sites-extras.yml`, com `so-cloudflare@file`, responde 403 à conexão do host no smoke
- [x] O whoami, sem a peça, continua respondendo 200 no smoke
- [x] A peça aparece na API do painel com `sourceRange` igual à lista do `trustedIPs` do `traefik.yml` (conferido no smoke)
- [x] Com a lista vazia, o Traefik sobe, o log mostra o AVISO e a peça fica só com `127.0.0.1/32`
- [x] O README e o guia de integração citam `so-cloudflare@file` e avisam que é só para nuvem laranja, e o `testes/docs.sh` confere isso
- [x] `testes/docs.sh`, `testes/deploy.sh` e `testes/smoke.sh` passam
- [x] Nenhum commit inclui `.scratch/`
