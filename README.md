# traefik-default

Modelo de borda (Traefik v3 + docker-socket-proxy) para qualquer VPS.

<!-- As demais seções (preparação do servidor, estrutura de pastas, guia
"como plugar um projeto", painel por túnel SSH etc.) entram nas próximas
etapas. As seções abaixo, sobre certificados, são autocontidas. -->

## Certificados (Let's Encrypt)

### Os dois emissores

O Traefik emite e renova os certificados sozinho, pelo protocolo ACME do
Let's Encrypt. Há dois emissores (`certResolvers`), definidos em
`traefik/traefik.yml`; cada site escolhe um por label:

| Emissor   | Desafio | Para domínios                          | Certificado                    |
|-----------|---------|----------------------------------------|--------------------------------|
| `le-dns`  | DNS-01 via API da Cloudflare | com DNS na Cloudflare (ex.: `conantorres.dev`) | `dominio` + `*.dominio` (curinga) |
| `le-http` | HTTP-01 na entrada `web` (porta 80) | com DNS sem API (ex.: `bbcontainermodular.com`, na Squarespace) | nomes exatos: `dominio` e `www.dominio` |

- **DNS-01**: o Let's Encrypt pede um registro TXT `_acme-challenge.<domínio>`
  com um valor aleatório. O Traefik cria esse registro pela API da Cloudflare,
  espera ele aparecer e apaga depois. Não precisa de porta aberta, e é o único
  desafio que permite curinga.
- **HTTP-01**: o Let's Encrypt acessa
  `http://<domínio>/.well-known/acme-challenge/<token>` na porta 80, e o
  Traefik responde. Exige que o domínio já aponte para a VPS e que a porta 80
  esteja aberta. Não permite curinga.

### Variáveis (`.env`)

Todas estão documentadas no `.env.example`:

- `ACME_AMBIENTE`: `staging` (padrão) ou `producao`. É **uma única
  variável** que muda o servidor ACME dos **dois** emissores.
- `ACME_EMAIL`: e-mail da conta ACME (opcional).
- `CF_DNS_API_TOKEN`: token da Cloudflare, usado só pelo `le-dns`.

Sem nenhuma delas a pilha sobe normalmente (em staging); só a emissão pelo
`le-dns` falha, com erro no log.

**Por que existe o `traefik/iniciar.sh`?** A configuração estática do Traefik
vem de uma única fonte: arquivo, flags ou variáveis `TRAEFIK_*`. Quando há
arquivo, as outras são ignoradas, e o YAML não lê variáveis de ambiente.
Então o `traefik/traefik.yml` é um modelo com marcadores (`__ACME_CA_SERVER__`,
`__ACME_EMAIL__`, `__ACME_AMBIENTE__`), e o `iniciar.sh` (ponto de entrada do
container) troca esses marcadores pelos valores do `.env`, grava a
configuração final em `/etc/traefik/traefik.yml` dentro do container e
executa o Traefik. O token não passa pelo script: o Traefik o lê direto do
ambiente.

### Para que serve o token da Cloudflare

O Traefik usa o token **só** para criar e remover automaticamente o registro
TXT `_acme-challenge` que o Let's Encrypt exige a cada emissão e renovação
DNS-01 (a cada ~60 dias). Ele não serve para mais nada: o Traefik não mexe
nos outros registros, nem no proxy da Cloudflare.

Como ele dá acesso de escrita ao DNS, o escopo é o mínimo possível:

- permissões `Zone / DNS / Edit` (criar/apagar o TXT) e `Zone / Zone / Read`
  (só leitura, para descobrir o ID da zona; a documentação do provedor
  Cloudflare do lego, usado pelo Traefik, pede as duas);
- recursos: **só as zonas escolhidas** (`Include / Specific zone`), nunca
  "All zones";
- sempre um *API Token*, nunca a *Global API Key*;
- opcional: restringir ao IP da VPS (Client IP Address Filtering).

Se o token vazar, o estrago fica limitado ao DNS das zonas escolhidas: dá
para revogá-lo no painel da Cloudflare e criar outro. Ele fica só no `.env`
do servidor, que nunca vai para o git.

### Onde ficam os certificados (`acme/`)

O diretório `acme/` do repositório é montado em `/acme` no container. Ali o
Traefik guarda contas e certificados, **um arquivo por emissor e por
ambiente**:

```
acme/le-dns-staging.json    acme/le-dns-producao.json
acme/le-http-staging.json   acme/le-http-producao.json
```

- O Traefik cria cada arquivo com permissão `600` (só o dono lê). Ele se
  recusa a usar um arquivo mais aberto; o `iniciar.sh` corrige a permissão
  ao iniciar, caso um arquivo volte de backup com outra.
- É um diretório do host (não volume nomeado), então sobrevive a
  `docker compose down -v`, à recriação do container e a reboots. Faça
  backup dele.
- Nunca vai para o git (está no `.gitignore`): contém chaves privadas.
- Separar por ambiente evita que, ao virar para produção, certificados de
  staging antigos continuem sendo servidos até vencer.

### Como um site pede o certificado (labels)

Com `le-dns` (domínio + curinga):

```yaml
- "traefik.http.routers.meusite.tls.certresolver=le-dns"
- "traefik.http.routers.meusite.tls.domains[0].main=dominio.com"
- "traefik.http.routers.meusite.tls.domains[0].sans=*.dominio.com"
```

Com `le-http` (nomes exatos, tirados da regra `Host(...)` de cada router):

```yaml
# router principal: Host(`dominio.com`)
- "traefik.http.routers.meusite.tls.certresolver=le-http"
# router do www (que redireciona para a raiz): Host(`www.dominio.com`)
- "traefik.http.routers.meusite-www.tls.certresolver=le-http"
```

O router do `www` também precisa de certificado (o visitante chega em
`https://www...` antes de ser redirecionado). Com `le-dns` ele já é coberto
pelo curinga; com `le-http`, ele mesmo pede o seu.

### Roteiro: testar DNS-01 localmente em staging

Valida o `le-dns` no seu computador, antes da VPS. DNS-01 não precisa que o
domínio aponte para você, então nenhum registro A é criado: só o TXT
temporário, feito pelo próprio Traefik. Usa o subdomínio de teste
`teste.conantorres.dev` e pede `teste.conantorres.dev` +
`*.teste.conantorres.dev`.

1. Crie um token na Cloudflare como descrito acima, restrito à zona
   `conantorres.dev` (se usar filtro de IP, inclua o IP da sua casa, ou crie
   um token só para este teste e apague depois).
2. Prepare o `.env`:
   ```sh
   cp .env.example .env
   # edite: ACME_AMBIENTE=staging, ACME_EMAIL=..., CF_DNS_API_TOKEN=...
   ```
3. Suba a borda (usa as portas 80 e 443 da sua máquina):
   ```sh
   docker network create proxy   # se ainda não existir
   docker compose up -d
   docker compose logs traefik | grep iniciar.sh
   # esperado: emissores ACME em 'staging' (https://acme-staging-v02...)
   ```
4. Suba um site de teste pedindo o curinga:
   ```sh
   docker run -d --name teste-dns01 --network proxy \
     -l traefik.enable=true \
     -l 'traefik.http.routers.teste-dns01.rule=Host(`teste.conantorres.dev`)' \
     -l traefik.http.routers.teste-dns01.entrypoints=websecure \
     -l traefik.http.routers.teste-dns01.tls.certresolver=le-dns \
     -l 'traefik.http.routers.teste-dns01.tls.domains[0].main=teste.conantorres.dev' \
     -l 'traefik.http.routers.teste-dns01.tls.domains[0].sans=*.teste.conantorres.dev' \
     -l traefik.http.services.teste-dns01.loadbalancer.server.port=80 \
     traefik/whoami:v1.12.0
   ```
5. Acompanhe a emissão (leva de alguns segundos a ~2 minutos, o tempo de o
   TXT propagar). Erros aparecem com `ERR` e o nome do emissor:
   ```sh
   docker compose logs -f traefik
   ```
   Durante a emissão dá para ver o TXT na Cloudflare ou com
   `dig +short TXT _acme-challenge.teste.conantorres.dev @1.1.1.1`.
6. Confira o certificado servido (emissor com `(STAGING)` e os dois nomes):
   ```sh
   echo | openssl s_client -connect 127.0.0.1:443 \
       -servername qualquer.teste.conantorres.dev 2>/dev/null \
     | openssl x509 -noout -issuer -ext subjectAltName
   # issuer=... (STAGING) ...
   # DNS:teste.conantorres.dev, DNS:*.teste.conantorres.dev
   ```
7. Confira o armazenamento e a persistência:
   ```sh
   ls -l acme/            # -rw------- ... le-dns-staging.json
   docker compose up -d --force-recreate traefik
   docker compose logs traefik   # não deve haver nova emissão
   ```
   Repita o passo 6: o certificado é o mesmo (mesmo número de série,
   `openssl x509 -noout -serial`).
8. Limpe: `docker rm -f teste-dns01` e `docker compose down`. Se o token era
   só para o teste, apague-o na Cloudflare.

### Checklist manual de emissão real

O smoke test (`testes/smoke.sh`) só confere que a pilha sobe sem token e
que os arquivos de `acme/` têm permissão `600`; ele não emite certificados.
Marque cada item ao validar:

**DNS-01 local em staging** (roteiro acima)
- [ ] Log mostra `emissores ACME em 'staging'`.
- [ ] Certificado com emissor `(STAGING)` e SAN `teste.conantorres.dev` +
      `*.teste.conantorres.dev`.
- [ ] `acme/le-dns-staging.json` com `-rw-------`.
- [ ] Após recriar o Traefik, o mesmo certificado continua sendo servido.

**HTTP-01 na VPS em staging**
- [ ] `ACME_AMBIENTE=staging` no `.env` da VPS.
- [ ] Registros A de `dominio` e `www.dominio` apontam para a VPS
      (`dig +short dominio.com` e `dig +short www.dominio.com`).
- [ ] Porta 80 aberta no firewall (o desafio chega por ela).
- [ ] O site sobe com `tls.certresolver=le-http` no router principal e no
      do `www`.
- [ ] `openssl s_client -connect dominio.com:443 -servername dominio.com`
      mostra emissor `(STAGING)` e SAN com o nome exato; o mesmo para
      `www.dominio.com`.
- [ ] `acme/le-http-staging.json` com `-rw-------`.

**Virada para produção**
- [ ] Trocar só `ACME_AMBIENTE=producao` no `.env` e rodar
      `docker compose up -d --force-recreate traefik` (nenhuma outra edição).
- [ ] Log mostra `emissores ACME em 'producao'
      (https://acme-v02.api.letsencrypt.org/directory)`.
- [ ] Os certificados passam a ter emissor sem `(STAGING)` (ex.: `R10`,
      `E5`) e o navegador mostra o cadeado sem aviso.
- [ ] Surgem `acme/le-dns-producao.json` e `acme/le-http-producao.json`,
      ambos `-rw-------`.

**Curinga x nomes exatos**
- [ ] Site em `le-dns`: SAN = `dominio` + `*.dominio`; um subdomínio novo
      (ex.: `blog.dominio`) é servido com o mesmo certificado, sem emissão nova.
- [ ] Site em `le-http`: SAN = só os nomes exatos (`dominio`, e o `www`
      com o certificado dele); nenhum curinga.

### Estudo extra: delegação do DNS-01 por CNAME

O `bbcontainermodular.com` tem DNS na Squarespace, sem API, por isso usa
HTTP-01 (sem curinga). Existe uma alternativa que permite DNS-01 (e curinga)
mesmo assim: **delegar só o registro do desafio** para uma zona que tem API.

Como funciona:

1. Uma única vez, à mão, na Squarespace, cria-se um CNAME:
   ```
   _acme-challenge.bbcontainermodular.com.  CNAME  bbcontainermodular.acme.conantorres.dev.
   ```
2. Na emissão, o Let's Encrypt consulta o TXT de
   `_acme-challenge.bbcontainermodular.com`, segue o CNAME e lê o TXT em
   `bbcontainermodular.acme.conantorres.dev`, que fica na Cloudflare.
3. O Traefik (lego) também segue o CNAME e cria o TXT na zona
   `conantorres.dev` pela API, com o mesmo token. Em versões recentes do
   lego isso é o comportamento padrão (`LEGO_DISABLE_CNAME_SUPPORT=true`
   desliga); confira na documentação da versão do Traefik em uso.

Prós: curinga e DNS-01 para um domínio sem API; a porta 80 deixa de ser
necessária para emitir. Contras: mais uma peça para entender e manter (o
CNAME não pode sumir); o token precisa de acesso à zona que recebe a
delegação; e um vazamento dele permitiria emitir certificados para o domínio
delegado. Por isso fica só como estudo: o modelo usa HTTP-01 para esses
domínios.
