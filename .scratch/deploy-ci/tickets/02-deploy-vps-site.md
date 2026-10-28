# 02: Script de deploy de um site (`conan-torres`) chamado pelo comando forçado

> **Difficulty:** Heavy: **suggested model:** Opus (Claude Code) / Opus or the strongest reasoning model available (Cursor). Suggestion only, use whatever model you have to hand.

**Spec:** ../SPEC.md

**What to build:** o script `deploy-vps`, versionado ao lado do script do cron. Recebe o projeto como argumento (vindo do `command=` do `authorized_keys`, nunca do GitHub) e o SHA por `SSH_ORIGINAL_COMMAND`. Para `conan-torres`: recusa `IMAGE_TAG` definido no `.env` da pasta (mensagem "versão travada"), faz `pull` + `up -d`, espera o container `healthy` (até 2 min, prazo ajustável só no teste), confere que o digest de `latest` em uso é o da tag do SHA, e sai ≠ 0 com mensagem legível em qualquer falha. Usa a mesma trava do cron, esperando a vez por tempo limitado. Sem rollback.

**Seams:**
- Seam 1: teste novo do script de deploy e do cron (estende o teste do ticket 01).

**Blocked by:** 01 (O cron pula os sites marcados…)

Status: ready-for-human

- [x] Projeto fora da lista fixa (`conan-torres`, `traefik`) é recusado sem chamar `docker`
- [x] SHA ausente, não hexadecimal ou de tamanho errado é recusado sem chamar `docker`
- [x] `IMAGE_TAG` no `.env` → recusa com mensagem de versão travada, sem `pull` nem `up`
- [x] Container que não fica `healthy` no prazo → falha com mensagem
- [x] Digest de `latest` diferente do da tag do SHA → falha com mensagem
- [x] Caminho feliz: `pull`, `up -d`, healthy, digest igual → código 0
- [x] Usa a mesma trava do cron (espera limitada, não desiste na hora)
- [x] Raízes e trava substituíveis por variável de ambiente só para teste; padrão = produção
- [x] Todos os casos acima cobertos pelo teste local
