# 04: Instalação do acesso do GitHub na VPS (usuário `deploy`, sudoers, chaves, Environment)

> **Difficulty:** Heavy: **suggested model:** Opus (Claude Code) / Opus or the strongest reasoning model available (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** o README da borda ganha o roteiro, que o dono roda na VPS, para: instalar o `deploy-vps` como root; criar o usuário `deploy` sem shell útil e fora do grupo `docker`; regra de sudoers que libera só o script com os dois argumentos permitidos; uma chave por repositório, cada linha do `authorized_keys` com `restrict` e `command=` fixando o projeto; gerar o `known_hosts` e conferir a impressão digital; criar o Environment `producao` (só `main`) em cada repositório com os secrets de host, chave e `known_hosts` (nomes definidos aqui e usados nos tickets 05 e 06). Mesmo estilo da seção do usuário `metricas`. O `docs.sh` confere os pontos.

**Seams:**
- Seam 2: `docs.sh` do traefik-default.

**Blocked by:** 02, 03

Status: ready-for-agent

- [ ] README: instalar o script, criar `deploy`, sudoers restrito ao script + argumentos
- [ ] README: linhas do `authorized_keys` com `restrict` e `command=` por projeto, uma chave por repositório
- [ ] README: `known_hosts` e conferência da impressão digital
- [ ] README: Environment `producao` limitado à `main`, nomes dos secrets
- [ ] README: script roda como root via sudo e usa o `docker login` do root para o GHCR
- [ ] `docs.sh` confere esses pontos e passa
