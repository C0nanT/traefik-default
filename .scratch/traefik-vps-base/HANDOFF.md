# Handoff: modelo base de Traefik para VPS

Última sessão: 2026-10-25. Este arquivo fica em `.scratch/` (versionado junto com SPEC e tickets).

## Onde parou

A especificação (`SPEC.md`, nesta pasta) está **implementada e testada localmente**. Os 8 tickets estão em `tickets/`. Smoke test final: **79 ok, 0 falhas**. Nada foi enviado ao GitHub e nenhum certificado real foi emitido ainda.

| Repositório | Branch de trabalho (checked out) | Último commit |
|---|---|---|
| `~/projects/traefik-default` | `feat/traefik-base` | `78f0add` |
| `~/projects/bbcontainer` | `feat/traefik-contract` | `bd73acf` |
| `~/projects/conan-torres` | `feat/traefik-contract` | `244d340` |

O `traefik-default` foi transformado em repositório git nesta sessão e ainda não tem remoto (não está no GitHub).

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

## Próximos passos (em ordem sugerida)

1. **Revisar as branches** dos três repositórios e juntar na `main`.
2. **Publicar o `traefik-default` no GitHub** (público). Depois:
   - criar a issue "Habilitar proxy da Cloudflare (nuvem laranja)": IPs confiáveis no Traefik, SSL "Full (strict)" e conferência do IP real nos logs;
   - conferir o link `github.com/c0nant/traefik-default` no README do bbcontainer.
3. **conan-torres no GitHub:**
   - fazer o push na `main` e ver o workflow "Build & Push Image" publicar `ghcr.io/c0nant/conan-torres` com as tags `latest` e SHA;
   - confirmar que o pacote ficou **privado**;
   - se o Actions estiver como somente leitura, liberar a escrita de pacotes.
4. **Teste local de DNS-01**, opcional mas recomendado para estudo:
   - criar o token da Cloudflare;
   - seguir o roteiro "teste local" do README, com `teste.conantorres.dev` em staging.
5. **VPS:**
   - seguir o checklist do README: Docker 28.0 ou mais recente, `ufw` liberando 22/80/443, `docker network create proxy`, pastas `/opt/traefik` e `/opt/apps/<projeto>`;
   - fazer login no GHCR com um token `read:packages`;
   - subir primeiro em `staging`, conferir e depois mudar para `producao`.
6. **Apontar o DNS** dos dois domínios para o IP da VPS. Na Cloudflare, deixar a nuvem **cinza**.
7. **Fechar os tickets** com as caixas que ficaram abertas (tabela abaixo) e marcar `Status: ready-for-human`.

## Caixas em aberto nos tickets

| Ticket | O que falta | Como resolver |
|---|---|---|
| 03 | Certificado DNS-01 real emitido em staging | Passo 4 |
| 05 | VPS limpa de pé seguindo só o README | Passo 5 |
| 06 | Push publica a imagem; imagem privada; container `healthy` | Passo 3 |
| 07 | bbcontainer atrás da pilha: HTTPS, cabeçalhos e redirecionamento do `www` | Passo 5 (ou local, com login no GHCR) |
| 08 | conan-torres atrás da pilha: HTTPS e redirecionamento do `www` | Passo 5 (ou local, com login no GHCR) |

Os tickets 01, 02 e 04 já estão completos (`ready-for-human`).

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
