# 06: conan-torres, imagem no GHCR e healthcheck

> **Dificuldade:** Difícil: **modelo sugerido:** Opus (Claude Code) / Opus ou o modelo de raciocínio mais forte disponível (Cursor). Só sugestão, use o modelo que tiver à mão.

**Spec:** ../SPEC.md

**O que construir:** no repositório conan-torres:
- um workflow do GitHub Actions que constrói e publica a imagem privada no GHCR (inspirado no `deploy-image.yml` do bbcontainer), com tags `latest` e SHA;
- um endereço de health que o healthcheck do container possa consultar.

A VPS deixa de construir esse projeto.

**Pontos de teste:**
- Nenhum deste repositório (a verificação é o workflow publicar a imagem e o healthcheck ficar `healthy` localmente)

**Bloqueado por:** nenhum (pode começar já)

Status: ready-for-agent

- [ ] Um push na `main` (depois do CI verde) publica `ghcr.io/<owner>/conan-torres` com as tags `latest` e SHA
- [ ] A imagem é privada
- [x] O endereço de health responde 200 sem depender da senha do leitor
- [ ] O container local fica `healthy` com o healthcheck definido
- [x] Os segredos (`READER_PASSWORD` etc.) continuam vindo só de variáveis de ambiente em runtime, nunca embutidos na imagem
