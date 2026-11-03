# 06: Conferência ao vivo

> **Difficulty:** Standard: **suggested model:** Sonnet (Claude Code) / Sonnet (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** a prova em produção de que a borda está fechada. É um teste único, pré-autorizado pelo dono, rodado do PC dele, que fica fora da Cloudflare:
1. `curl --resolve conantorres.dev:443:<IP da VPS> https://conantorres.dev/` deve dar 403.
2. Cerca de 150 requisições rápidas, pela Cloudflare, a um caminho inexistente devem mostrar 429. As requisições param no primeiro bloco de 429 e não são repetidas.
3. A home pela Cloudflare deve continuar respondendo 200.

O resultado de cada passo é registrado para o ticket 07.

**Seams:** None

**Blocked by:** 05 (merge e deploy do conan-torres)

Status: ready-for-agent

- [x] A conexão direta na origem recebeu 403
- [x] A rajada pela Cloudflare recebeu 429
- [x] A home pela Cloudflare respondeu 200 depois da rajada
- [ ] O teste rodou uma vez só, sem repetição
