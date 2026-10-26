# 05: README e guia "como plugar um projeto"

> **Dificuldade:** Médio: **modelo sugerido:** Sonnet (Claude Code) / Sonnet (Cursor). Só sugestão, use o modelo que tiver à mão.

**Spec:** ../SPEC.md

**O que construir:** documentação para usar o modelo numa VPS nova e plugar qualquer site.
- **README:**
  - checklist da VPS (instalar Docker, firewall com só 22/80/443, criar a rede `proxy`, estrutura `/opt/traefik` e `/opt/apps/<projeto>`);
  - como subir a pilha;
  - como fixar e atualizar a versão do Traefik.
- **Guia de integração:** requisitos de um site:
  - imagem privada no GHCR construída no CI, com login da VPS por token `read:packages`;
  - sem `ports:`;
  - rede `proxy`;
  - healthcheck;
  - labels usando as peças compartilhadas e o emissor certo para o DNS (`le-dns` ou `le-http`);
  - um compose de exemplo completo, que é o mesmo usado pelo whoami do smoke test;
  - deploy manual agora, com GitHub Actions via SSH como evolução.

**Pontos de teste:**
- Smoke test local da pilha (o compose de exemplo do guia é o que o smoke test usa)

**Bloqueado por:** 02: Peças compartilhadas; 03: Emissores de certificado; 04: Logs de acesso e métricas internas

Status: ready-for-agent

- [ ] Seguindo só o README, uma VPS limpa fica com a pilha de pé
- [x] O compose de exemplo do guia é o mesmo do smoke test (sem divergência)
- [x] O guia explica quando usar `le-dns` e quando usar `le-http`
- [x] O guia lista os nomes do contrato: `web`, `websecure`, `proxy`, `le-dns`, `le-http` e as peças `@file`
- [x] A seção "próximos passos" cita a nuvem laranja da Cloudflare e o Grafana
