# Handoff: modelo base de Traefik para VPS

Este arquivo fica em `.scratch/` (versionado junto com SPEC e tickets).

## Onde parou

Última atualização: 2026-10-26. **Os 8 tickets estão `ready-for-human`, sem caixas abertas.**

| Repositório | `main` | GitHub |
|---|---|---|
| `traefik-default` | publicado | <https://github.com/C0nanT/traefik-default> (público) |
| `bbcontainer` | `bd73acf` | imagem privada no GHCR |
| `conan-torres` | `fb2cef6` | imagem privada no GHCR (`latest` + SHA) |

**VPS (Hetzner, Ubuntu 24.04; IP fora do repositório)** reconstruída do zero e montada só pelo README: borda em `/opt/traefik` com `ACME_AMBIENTE=producao`; `bbcontainer` e `conan-torres` em `/opt/apps/<projeto>` (`healthy`), certificados de produção emitidos (`le-http` para o bbcontainer, curinga `le-dns` para o conantorres.dev).

- `bbcontainermodular.com`: **no ar** pela VPS (DNS já apontava para ela).
- `conantorres.dev`: **no ar** pela VPS (DNS na Cloudflare trocado em 2026-10-26, nuvem cinza; `www` é CNAME para a raiz).

## Decisões tomadas (resumo; detalhes na SPEC)

- Este repositório tem **só a pilha de borda**: Traefik `v3.7.16` mais o `docker-socket-proxy`, que dá ao Traefik acesso só de leitura ao Docker. Cada site fica no próprio repositório e se pluga seguindo `docs/como-plugar-um-projeto.md`.
- **Nomes do padrão:** entradas `web` (80) e `websecure` (443), rede `proxy`, emissores `le-dns` e `le-http`, peças `seguranca@file`, `compressao@file` e `www-para-raiz@file`.
- **Certificados no modelo híbrido:**
  - `conantorres.dev` usa DNS-01 pela Cloudflare, com curinga.
  - `bbcontainermodular.com` usa HTTP-01, porque o DNS fica na Squarespace, que não tem API. Esse DNS não vai ser transferido.
- **Teste ou produção:** `ACME_AMBIENTE=staging|producao` no `.env` alterna os dois emissores. O `traefik/iniciar.sh` monta o `traefik.yml` na inicialização, porque o Traefik não lê variáveis dentro do YAML.
- **Painel e métricas:** ficam só em `127.0.0.1`, portas 8080 e 8082, e você acessa por túnel SSH. O painel responde só pela rede `painel`; os containers dos sites recebem 403.
- **Token da Cloudflare:** precisa de `Zone:Zone:Read` e `Zone:DNS:Edit`, limitadas às zonas escolhidas.
- **Imagens dos sites:** privadas no GHCR, construídas no CI, nunca na VPS. O deploy é manual (`docker compose pull && up -d`), e o deploy pelo CI via SSH fica como evolução.

## Próximos passos

1. **Vercel:** remover `conantorres.dev` e `www.conantorres.dev` do projeto (Settings → Domains).
2. Issue #1 do `traefik-default`: nuvem laranja (opcional).
3. Evoluções: deploy pelo CI via SSH; token da Cloudflare por arquivo (`CF_DNS_API_TOKEN_FILE`); refatorar duplicação dos helpers de teste; healthcheck no exemplo do whoami.

## Como verificar que está tudo certo

- No `traefik-default`, rodar `bash testes/smoke.sh`. Ele usa as portas 80, 443, 8080 e 8082 do seu computador, então elas precisam estar livres. O resultado esperado é `0 falha(s)`.
- `bash testes/docs.sh` confere a documentação.

## Riscos aceitos e pontos de atenção

- **Containers vizinhos:** um container na rede `proxy` consegue chamar outro site direto, sem passar pelo Traefik, e forjar o `X-Forwarded-For`. O risco é aceito porque só seus próprios containers estão nessa rede. Está documentado no AGENTS.md do conan-torres.
- **Token visível:** o token da Cloudflare entra como variável de ambiente, então quem tem acesso ao Docker consegue vê-lo com `docker inspect`. Uma melhoria futura é passar por arquivo (`CF_DNS_API_TOKEN_FILE`).
- **Docker e firewall:** portas publicadas com `ports:` passam por fora do `ufw`. Por isso o guia proíbe `ports:` nos sites.
- **Teste de TLS 1.1:** o smoke test precisa de um `openssl` que ainda aceite `-tls1_1`.

## Arquivos úteis

- Especificação: `.scratch/traefik-vps-base/SPEC.md`
- Tickets: `.scratch/traefik-vps-base/tickets/`
- Anotações técnicas dos subagentes (versões, labels, decisões de cada ticket): `~/projects/.traefik-notes/`
- Guia para plugar sites: `docs/como-plugar-um-projeto.md`
