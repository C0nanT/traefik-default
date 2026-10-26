# 01: Pilha mínima de borda com smoke test

> **Dificuldade:** Difícil: **modelo sugerido:** Opus (Claude Code) / Opus ou o modelo de raciocínio mais forte disponível (Cursor). Só sugestão, use o modelo que tiver à mão.

**Spec:** ../SPEC.md

**O que construir:** um `docker compose up` neste repositório sobe o Traefik v3 (versão exata fixada) e o `docker-socket-proxy` (o intermediário que dá ao Traefik acesso só de leitura ao Docker). A configuração estática fica num YAML comentado, com as entradas `web`/`websecure` e o redirecionamento global de HTTP para HTTPS. O provedor Docker usa `exposedByDefault=false` e lê o Docker pelo socket-proxy, numa rede interna. O painel fica habilitado, mas não roteado publicamente. A rede externa `proxy` é usada pelos sites. O Traefik tem healthcheck (ping) e `restart: unless-stopped`. Um `.env.example` inicial lista as variáveis. Um script de smoke test sobe a pilha com um app de exemplo (`traefik/whoami`) e um container sem label, verifica o comportamento com `curl` e derruba tudo no final.

**Pontos de teste:**
- Smoke test local da pilha

**Bloqueado por:** nenhum (pode começar já)

Status: ready-for-human

- [x] Traefik e socket-proxy sobem saudáveis; o socket do Docker não é montado no Traefik
- [x] O socket-proxy libera só os endpoints de leitura necessários e não está na rede `proxy`
- [x] O smoke test confirma: HTTP redireciona permanentemente para HTTPS; o whoami responde via HTTPS (certificado padrão aceito com `-k`)
- [x] O smoke test confirma: um container sem `traefik.enable=true` não é roteado
- [x] O smoke test confirma: painel e API não respondem nas portas 80/443
- [x] O smoke test termina com código diferente de zero quando alguma verificação falha e sempre derruba a pilha
- [x] `.env` e `acme.json` estão no `.gitignore`
