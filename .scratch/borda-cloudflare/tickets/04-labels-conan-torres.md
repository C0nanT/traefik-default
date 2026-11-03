# 04: conan-torres liga as duas peças

> **Difficulty:** Light: **suggested model:** Haiku (Claude Code) / claude-4.5-haiku-thinking (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** no repositório `conan-torres`, os roteadores `conan-torres` e `conan-torres-www` ganham `so-cloudflare@file` e `limite-taxa@file`, nesta ordem e antes das peças que já usam. Sai um PR próprio, com texto neutro. O merge só acontece no ticket 05, depois que as peças estiverem em produção.

**Seams:** None

**Blocked by:** 03 (merge e deploy da borda)

Status: ready-for-human

- [x] Os dois roteadores citam `so-cloudflare@file` e `limite-taxa@file` antes das peças que já usavam
- [x] As checagens do repositório conan-torres passam (`pnpm check`, `typecheck`, `build`)
- [x] O PR está aberto, com título e texto neutros e sem citar a falha
