# 01: Remover o deploy por SSH da borda

> **Difficulty:** Standard: **suggested model:** Sonnet (Claude Code) / Sonnet (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** o traefik-default volta a ter só o deploy pelo cron. Saem o workflow de deploy da borda, o script `deploy-vps`, o suporte ao marcador `.deploy-pelo-ci` no script do cron, o ecossistema `github-actions` do Dependabot e as seções do README ("Deploy pelo CI", "Checklist do primeiro deploy"). A seção "Deploy" do guia de plugar projeto descreve só cron e manual. O teste local de deploy fica reduzido ao cron. O `docs.sh` volta a reprovar qualquer arquivo em `.github/workflows` e confere que não sobrou referência a `deploy-vps` nem `.deploy-pelo-ci`. O README ganha um roteiro curto, rodado pelo dono, para limpar a VPS (sudoers do deploy com `visudo -c`, `deluser --remove-home deploy`, apagar o script instalado, reinstalar o cron) e o GitHub (apagar o Environment `producao` nos dois repositórios). HANDOFF: item do deploy pelo CI fechado como "descartado (2026-10-28)", motivo: não expor a porta 22. A spec antiga (`.scratch/deploy-ci/`) recebe uma nota no topo dizendo que foi substituída.

**Seams:**
- Seam 1: teste local do cron (reduzido ao cron).

**Blocked by:** None (can start immediately)

Status: ready-for-human

- [x] Workflow da borda, `deploy-vps` e marcador removidos; `.github/workflows` vazio
- [x] Dependabot sem `github-actions`
- [x] README e guia sem deploy pelo CI; guia descreve cron e manual
- [x] Roteiro de limpeza da VPS e do GitHub no README
- [x] Teste local só do cron passa; `docs.sh` passa e barra restos do SSH
- [x] HANDOFF e spec antiga atualizados
