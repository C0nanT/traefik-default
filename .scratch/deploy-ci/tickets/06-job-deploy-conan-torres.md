# 06: Job de deploy no workflow do conan-torres

> **Difficulty:** Heavy: **suggested model:** Opus (Claude Code) / Opus or the strongest reasoning model available (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** no repositório **conan-torres**, um job de deploy que depende do `build-push` no workflow de imagem e herda as mesmas condições (só `main`, CI verde ou disparo manual na `main`), no Environment `producao`: grava chave e `known_hosts` em arquivos temporários, `ssh` com `StrictHostKeyChecking=yes` mandando o SHA construído, depois `curl` em https://conantorres.dev exigindo 200. O `concurrency` existente segue enfileirando. README e AGENTS do conan-torres passam a dizer que o deploy é pelo CI, que o cron pula o site pelo marcador e que `IMAGE_TAG` no `.env` trava o deploy (CI fica vermelho até remover).

**Seams:**
- None (sem teste local; validado pelo checklist manual do ticket 07).

**Blocked by:** 02, 04

Status: ready-for-agent

- [ ] Job `needs: build-push` com as mesmas condições de gatilho
- [ ] Manda o SHA exato que o `build-push` usou
- [ ] Environment `producao`, secrets nomeados no ticket 04, `ssh` direto sem action de terceiros
- [ ] `curl` em https://conantorres.dev exige 200
- [ ] README/AGENTS atualizados (deploy pelo CI, marcador, `IMAGE_TAG` trava)
- [ ] YAML validado localmente; CI do conan-torres continua verde
