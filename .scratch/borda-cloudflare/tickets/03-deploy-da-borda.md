# 03: Merge e deploy da borda

> **Difficulty:** Light: **suggested model:** Haiku (Claude Code) / claude-4.5-haiku-thinking (Cursor). Suggestion only, use whatever model you have to hand.

> **Gate:** human: o dono faz o merge do PR do traefik-default e, na VPS, roda `cd /opt/traefik && git pull && docker compose up -d`

**Spec:** ../SPEC.md

**What to build:** as duas peças existem em produção antes de qualquer site citá-las. Depois da confirmação do dono, o agente confere, só lendo, que o Traefik está saudável e que `so-cloudflare@file` e `limite-taxa@file` aparecem na API do painel pelo túnel (127.0.0.1:8080). Também confere que o bbcontainer e o conan-torres seguem respondendo como antes, olhando os logs de acesso no Loki, sem requisição ativa aos sites.

**Seams:** None

**Blocked by:** 02 (peça `limite-taxa` por visitante real)

Status: ready-for-human

- [x] O PR tem título e texto neutros e não inclui `.scratch/`
- [x] O dono confirmou o merge e o deploy na VPS
- [x] A API do painel em produção lista as duas peças com as faixas da Cloudflare
- [x] O log do Traefik não mostra o AVISO de lista vazia
- [x] Os logs de acesso não mostram 403 nem 429 novos no bbcontainer e no conan-torres depois do deploy
