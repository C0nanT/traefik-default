# 07: Guia de plugar projeto, HANDOFF e checklist do primeiro deploy

> **Difficulty:** Light: **suggested model:** Haiku (Claude Code) / claude-4.5-haiku-thinking (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** a seção "Deploy" do guia de plugar um projeto deixa de tratar o CI por SSH como evolução: descreve o CI como caminho dos sites com `.deploy-pelo-ci` e o cron como opção. README da borda ganha o checklist manual do primeiro deploy, na ordem segura da spec (instalar na VPS → Environments e secrets → marcador → só então mesclar o job do conan-torres), incluindo: primeiro deploy do site e da borda, chave de um repositório não faz deploy do outro nem abre shell/túnel, falha forçada (`IMAGE_TAG`) com execução vermelha e e-mail, cron não mexe mais no conan-torres, e o ajuste de notificação da conta (e-mail só para falha). HANDOFF: item 4 fechado com resumo.

**Seams:**
- Seam 2: `docs.sh` do traefik-default.

**Blocked by:** 05, 06

Status: ready-for-human

- [x] Guia: seção "Deploy" descreve CI e cron como são
- [x] README: checklist manual na ordem segura, com todos os itens listados
- [x] HANDOFF: item 4 marcado como fechado com resumo
- [x] `docs.sh` confere guia e checklist e passa
