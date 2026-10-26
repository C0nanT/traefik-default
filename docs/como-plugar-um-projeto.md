# Como plugar um projeto na borda

Guia para colocar qualquer site atrás do Traefik deste repositório. O setup da
VPS e da pilha está no [README](../README.md); aqui é só o lado do site.

## O contrato

Nomes oficiais que todo site usa (definidos nesta pilha, não invente outros):

| Item | Nome | O que é |
|------|------|---------|
| Entrada HTTP | `web` | porta 80; redireciona sozinha para HTTPS (global) |
| Entrada HTTPS | `websecure` | porta 443; TLS ligado por padrão |
| Rede Docker | `proxy` | externa, criada uma vez por VPS; Traefik e sites entram nela |
| Emissor DNS-01 | `le-dns` | certificado `dominio` + `*.dominio` (DNS na Cloudflare) |
| Emissor HTTP-01 | `le-http` | certificado dos nomes exatos (DNS sem API) |
| Peça: segurança | `seguranca@file` | HSTS, X-Frame-Options DENY, nosniff, Referrer-Policy |
| Peça: compressão | `compressao@file` | gzip/brotli/zstd acima de 1 KB |
| Peça: www para raiz | `www-para-raiz@file` | redirect permanente `www.x` para `x`, preservando caminho e query |

O TLS mínimo 1.2 vale para todos os routers sem nenhuma label.

## Requisitos de um site

1. **Imagem privada no GHCR, construída no CI.** A VPS nunca compila nada
   (sem `build:` no compose de produção).
2. **Sem `ports:`.** Só `expose` (documentação) e a rede externa `proxy`. Todo
   tráfego entra pelo Traefik.
3. **Rede `proxy`** declarada como externa, e `traefik.docker.network=proxy`.
4. **Healthcheck obrigatório**, para o Docker (e você) saberem se o app está
   saudável: no serviço do compose **ou** como `HEALTHCHECK` no Dockerfile da
   imagem (o container herda). Use um endpoint próprio (ex.: `/api/health`).
5. **Labels** com `traefik.enable=true` (sem ela o Traefik ignora o
   container), router em `websecure`, as peças `@file` e o emissor certo.
6. Na VPS, o site mora em `/opt/apps/<projeto>/` com **só**
   `docker-compose.yml` e `.env`.

## O compose de exemplo (o mesmo do smoke test)

O exemplo completo é o arquivo
[`exemplos/whoami/docker-compose.yml`](../exemplos/whoami/docker-compose.yml).
Ele é o compose que o smoke test (`testes/smoke.sh`) sobe, e é a **única**
cópia das labels base (router, `www`, peças, serviço): este guia não as
repete, para os dois nunca divergirem. Leia o arquivo; os comentários
explicam cada label. Copie-o e troque `whoami` pelo nome do projeto.

Duas particularidades, por escolha:

- **Healthcheck.** A imagem `traefik/whoami` é `scratch` (sem shell nem
  `wget`), então não existe healthcheck possível nela. Em vez de trocar o app
  de exemplo ou ter dois composes, o exemplo traz o bloco `healthcheck`
  **comentado**, pronto para descomentar e apontar para o endpoint de saúde
  do app. Em qualquer site real ele é obrigatório (no compose ou no
  Dockerfile). `wget`/`curl` precisam existir na imagem do app; senão use um
  binário do próprio app.
- **Emissor.** O exemplo não pede certificado (o domínio do smoke é
  fictício). As linhas a acrescentar para `le-dns` ou `le-http` estão logo
  abaixo, e só aqui.

## Qual emissor usar

| Se o DNS do domínio está... | Use | Pede |
|---|---|---|
| na Cloudflare (tem API) | `le-dns` | `dominio` + `*.dominio` (curinga) |
| em provedor sem API (ex.: Squarespace) | `le-http` | `dominio` e `www.dominio` (nomes exatos) |

`le-http` exige que o domínio já aponte para a VPS e a porta 80 esteja aberta.
Não faz curinga. Mais sobre os dois (e o token da Cloudflare, com permissões
`Zone / DNS / Edit` + `Zone / Zone / Read` só nas zonas escolhidas) no
[README](../README.md#certificados-lets-encrypt).

### Certificado: as linhas a acrescentar

Esta é a referência única das labels de certificado (o README e o exemplo
apontam para cá). Acrescente **um** dos blocos às labels do exemplo, com
`meusite` = nome do router do projeto (único na VPS) e `dominio.com` = o
domínio.

**`le-dns` (curinga)**: só no router principal; pede `dominio` + `*.dominio`.

```yaml
  - "traefik.http.routers.meusite.tls.certresolver=le-dns"
  - "traefik.http.routers.meusite.tls.domains[0].main=dominio.com"
  - "traefik.http.routers.meusite.tls.domains[0].sans=*.dominio.com"
```

O router do `www` é coberto pelo curinga e não precisa de `certresolver`.

**`le-http` (nomes exatos)**: nos dois routers, sem `tls.domains` (cada um
pede o nome da sua regra `Host(...)`).

```yaml
  - "traefik.http.routers.meusite.tls.certresolver=le-http"
  - "traefik.http.routers.meusite-www.tls.certresolver=le-http"
```

O router do `www` **precisa** do `certresolver`: o visitante chega em
`https://www...` antes do redirect, e sem curinga ninguém cobre esse nome.

Regras comuns: não declare redirect HTTP para HTTPS (é global), nem regex de
www (use `www-para-raiz@file`), nem `tls=true`. O router do `www` sempre
precisa de `service=<serviço do site>`, porque o redirect não chega ao app.

## Imagem privada no GHCR

1. **No CI** (GitHub Actions do repositório do site): faça login em
   `ghcr.io` com o `GITHUB_TOKEN`, construa e dê `push` de
   `ghcr.io/<usuario>/<projeto>:<tag>` (use tags de versão ou `sha`, não só
   `latest`).
2. **Na VPS**, uma vez: crie um *Personal Access Token (classic)* só com o
   escopo **`read:packages`** (somente leitura) e rode:
   ```bash
   echo "$TOKEN" | docker login ghcr.io -u <usuario> --password-stdin
   ```
   A credencial fica em `~/.docker/config.json` do usuário que roda o
   `docker compose`. Se vazar, o estrago é só ler imagens; revogue o token.

## Deploy

**Manual (hoje).** Na VPS:

```bash
cd /opt/apps/<projeto>
docker compose pull && docker compose up -d
docker compose ps     # o serviço deve aparecer como (healthy)
```

**GitHub Actions por SSH (evolução).** Depois do push da imagem, um passo do
workflow entra na VPS por SSH (chave dedicada, guardada em *secrets*, de
preferência com usuário restrito) e roda os mesmos dois comandos acima. É o
mesmo deploy, só disparado pelo CI. Watchtower foi descartado (projeto
arquivado).

## Checklist antes de subir um site

- [ ] Imagem no GHCR; `docker login ghcr.io` feito na VPS
- [ ] Sem `ports:`; rede `proxy` externa
- [ ] `healthcheck` presente
- [ ] `traefik.enable=true`, `entrypoints=websecure`, `middlewares` com as peças
- [ ] Emissor certo para o DNS (`le-dns` ou `le-http`) e router `-www`
- [ ] Nome do router único na VPS
- [ ] Primeiro teste com `ACME_AMBIENTE=staging`
