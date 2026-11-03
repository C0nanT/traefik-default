# 05: Merge e deploy do conan-torres

> **Difficulty:** Light: **suggested model:** Haiku (Claude Code) / claude-4.5-haiku-thinking (Cursor). Suggestion only, use whatever model you have to hand.

> **Gate:** human: o dono faz o merge do PR do conan-torres; o cron `atualizar-apps` publica em até 10 min

**Spec:** ../SPEC.md

**What to build:** as labels novas do conan-torres estão em produção. Depois da confirmação do dono, o agente confere no Loki que o cron `atualizar-apps` atualizou o conan-torres e que, depois disso, o roteador não tem erro e o site segue com 200 pelo tráfego normal. A conferência é só de leitura.

**Seams:** None

**Blocked by:** 04 (conan-torres liga as duas peças)

Status: ready-for-agent

- [x] O dono confirmou o merge
- [ ] O log do `atualizar-apps` mostra o conan-torres atualizado depois do merge
- [x] O Traefik não mostra erro de peça inexistente para os roteadores do conan-torres
- [x] O log de acesso mostra 200 nos roteadores do conan-torres depois do deploy
