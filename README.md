# Traefik na VPS

Modelo de borda (Traefik v3 + docker-socket-proxy) para qualquer VPS: HTTPS
automático (Let's Encrypt), peças de segurança reaproveitáveis e um contrato
simples para plugar sites. Cada site vive no próprio repositório e entra pelo
[guia de integração](docs/como-plugar-um-projeto.md).

Índice: [Checklist da VPS](#checklist-da-vps) ·
[Subir a pilha](#subir-a-pilha) ·
[Fixar e atualizar a versão do Traefik](#fixar-e-atualizar-a-versão-do-traefik) ·
[Plugar um site](docs/como-plugar-um-projeto.md) ·
[Painel e métricas](#painel-e-métricas-via-túnel-ssh) ·
[Certificados](#certificados-lets-encrypt) ·
[Próximos passos](#próximos-passos)

## Checklist da VPS

Faça uma vez por servidor (Debian/Ubuntu; ajuste ao seu sistema).

1. **Instalar o Docker** (Engine + plugin Compose), pelo repositório oficial:
   <https://docs.docker.com/engine/install/>. Confira com
   `docker compose version`. Adicione seu usuário ao grupo `docker`
   (`sudo usermod -aG docker $USER`, e entre de novo na sessão).
   Versões mínimas: Docker Engine 28.0+ (API 1.48) e Compose 2.33+, exigidas
   pelo `gw_priority` da rede `painel` (sem isso o painel fica inacessível
   pelo túnel). Confira com `docker version`.
2. **Firewall com só 22, 80 e 443** (exemplo com `ufw`; o 22 primeiro, para
   não se trancar para fora). Atenção: portas publicadas pelo Docker com
   `ports:` passam por fora do `ufw` (o Docker escreve as próprias regras de
   iptables). Por isso o guia proíbe `ports:` nos sites e o painel/métricas
   só são publicados em `127.0.0.1`:
   ```bash
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow 22/tcp
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw enable
   ```
   Se o provedor tiver firewall de rede
   (security group), libere lá as mesmas três portas.
3. **Criar a rede `proxy`** (externa, compartilhada por Traefik e sites):
   ```bash
   docker network create proxy
   ```
4. **Estrutura de pastas**:
   ```
   /opt/traefik          este repositório (a borda)
   /opt/apps/<projeto>   um por site: só docker-compose.yml e .env
   ```
   ```bash
   sudo mkdir -p /opt/traefik /opt/apps
   sudo chown "$USER": /opt/traefik /opt/apps
   ```
5. **DNS**: aponte os registros A do domínio (e do `www`) para o IP da VPS.
   Na Cloudflare comece em "só DNS" (nuvem cinza).
6. **Atualização automática dos sites** (cron a cada 10 min). O script
   `vps/atualizar-apps.sh` roda `docker compose pull && up -d` em cada
   `/opt/apps/*/` (só recria o que mudou) e limpa imagens antigas. Push na
   `main` de um site → no ar em até ~10 min depois do CI. Log só de mudanças
   e erros em `/var/log/atualizar-apps.log`, com rotação semanal:
   ```bash
   sudo install -m 755 /opt/traefik/vps/atualizar-apps.sh /usr/local/bin/atualizar-apps.sh
   sudo install -m 644 /opt/traefik/vps/atualizar-apps.cron /etc/cron.d/atualizar-apps
   sudo install -m 644 /opt/traefik/vps/atualizar-apps.logrotate /etc/logrotate.d/atualizar-apps
   ```
   Rode como `root` (o cron usa o `docker login ghcr.io` de `/root`). Para
   atualizar na hora, sem esperar: `cd /opt/apps/<projeto> && docker compose
   pull && docker compose up -d`.

## Subir a pilha

```bash
git clone <url-deste-repositório> /opt/traefik
cd /opt/traefik
cp .env.example .env
chmod 600 .env
$EDITOR .env          # ACME_AMBIENTE, ACME_EMAIL, CF_DNS_API_TOKEN (se usar le-dns)
docker compose up -d
docker compose ps     # traefik e socket-proxy devem estar (healthy)
docker compose logs traefik | grep iniciar.sh   # confirma o ambiente ACME
```

Comece sempre em `ACME_AMBIENTE=staging` (o padrão). A virada para produção é
trocar só essa variável e rodar
`docker compose up -d --force-recreate traefik`; veja o
[checklist de emissão](#checklist-manual-de-emissão-real).

Depois, plugue cada site seguindo o
[guia de integração](docs/como-plugar-um-projeto.md). Verificação rápida sem
subir nada: `docker compose config -q`.

## Fixar e atualizar a versão do Traefik

As imagens estão **fixadas**, nunca `latest`: nada muda sozinho. Cada tag
aparece em um único arquivo:

- `docker-compose.yml`: `traefik:v3.x.y`,
  `tecnativa/docker-socket-proxy:vX.Y.Z` e `prom/node-exporter:vX.Y.Z`;
- `exemplos/whoami/docker-compose.yml`: `traefik/whoami:vX.Y.Z` (app de
  exemplo e do smoke test).

O smoke test não repete nenhuma delas: usa a imagem do Traefik do container
em execução e lê a do whoami do exemplo.

Para atualizar, de propósito:

1. Leia as notas de versão do Traefik
   (<https://github.com/traefik/traefik/releases>), sobretudo em mudança de
   versão maior/menor. Para o node exporter, as de
   <https://github.com/prometheus/node_exporter/releases> (nomes de métricas
   podem mudar e quebrar painéis/alertas do Grafana).
2. Teste antes: no seu computador, troque a tag em `docker-compose.yml`
   (só ali) e rode `testes/smoke.sh` (usa as portas 80/443 e
   127.0.0.1:8080/8082/9100 da máquina; não rode na VPS com a pilha de pé).
3. Na VPS, troque a tag em `docker-compose.yml` (commit + pull, ou edição
   direta) e então:
   ```bash
   docker compose pull
   docker compose up -d
   docker compose ps && docker compose logs --tail 50 traefik
   docker compose logs --tail 50 node-exporter   # se trocou essa tag
   ```
4. Para voltar atrás, restaure a tag anterior e repita o `up -d`. Faça
   backup de `acme/` antes de atualizar.

Os arquivos de `acme/` e o `.env` ficam fora do controle de versão e
sobrevivem à troca de imagem.

## Painel e métricas via túnel SSH

O painel/API do Traefik (porta 8080), as métricas Prometheus do Traefik
(porta 8082) e as do host, pelo node exporter (porta 9100), **não** são
acessíveis pela internet: nunca respondem em 80/443. O `docker-compose.yml`
publica essas três portas apenas no loopback da VPS (`127.0.0.1:8080`,
`127.0.0.1:8082` e `127.0.0.1:9100`), então só se chega a elas de dentro do
servidor, por um túnel SSH.

No seu computador:

```bash
ssh -N -L 8080:127.0.0.1:8080 -L 8082:127.0.0.1:8082 -L 9100:127.0.0.1:9100 usuario@IP_DA_VPS
```

Com o túnel aberto, no seu navegador/terminal:

- Painel: <http://localhost:8080/dashboard/> (a barra final é obrigatória)
- API: <http://localhost:8080/api/overview>
- Métricas do Traefik: <http://localhost:8082/metrics>
- Métricas do host (node exporter): <http://localhost:9100/metrics>

Se a porta local já estiver em uso, troque o primeiro número
(ex.: `-L 9090:127.0.0.1:8080`). Feche o túnel com `Ctrl+C`.

**Por que os sites não leem o painel.** Os containers da rede `proxy` (os
sites) alcançam o Traefik direto, inclusive a porta 8080, sem passar pelo
host. Por isso o painel/API não usa `api.insecure` (que responderia a
qualquer um ali): o `traefik/iniciar.sh` gera um router para ele, só na
entrada interna 8080, que aceita **uma** origem, o gateway da rede `painel`
(só do Traefik). É desse IP que o Docker entrega as conexões feitas em
`127.0.0.1:8080` no host, como as do túnel. Um site vizinho recebe `403`,
mesmo forjando `X-Forwarded-For`; o `/ping` do healthcheck continua livre. O
smoke test confere isso (`testes/verificacoes/05-painel.sh`).

As métricas são outra história, de propósito: containers na rede `proxy`
(ex.: um Prometheus futuro) alcançam `http://traefik:8082/metrics`, sem passar
pelo host. Já o node exporter não: ele usa a rede do host
(`network_mode: host`), fora da rede `proxy`, e escuta só em
`127.0.0.1:9100`. Nenhum container vizinho o alcança, nem pelo gateway da
rede `proxy`; o smoke test confere isso
(`testes/verificacoes/06-node-exporter.sh`).

### Logs de acesso

O Traefik grava logs de acesso em JSON na saída padrão do container, com
rotação do Docker (5 arquivos de 10 MB):

```bash
docker compose logs -f traefik
```

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

Cada site escolhe o emissor por label no próprio router. As linhas exatas de
`le-dns` e `le-http` ficam num lugar só: o guia, em
[Certificado: as linhas a acrescentar](docs/como-plugar-um-projeto.md#certificado-as-linhas-a-acrescentar).
Em resumo: com `le-dns` o router principal pede `dominio` + `*.dominio` e o
`www` já fica coberto pelo curinga; com `le-http` cada router (o principal e
o do `www`, que o visitante acessa antes do redirect) pede o seu nome exato.

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
4. Suba um site de teste pedindo o curinga (com a mesma imagem fixada no
   exemplo, lida de `exemplos/whoami/docker-compose.yml`):
   ```sh
   WHOAMI="$(DOMINIO=x docker compose -f exemplos/whoami/docker-compose.yml config --images)"
   docker run -d --name teste-dns01 --network proxy \
     -l traefik.enable=true \
     -l 'traefik.http.routers.teste-dns01.rule=Host(`teste.conantorres.dev`)' \
     -l traefik.http.routers.teste-dns01.entrypoints=websecure \
     -l traefik.http.routers.teste-dns01.tls.certresolver=le-dns \
     -l 'traefik.http.routers.teste-dns01.tls.domains[0].main=teste.conantorres.dev' \
     -l 'traefik.http.routers.teste-dns01.tls.domains[0].sans=*.teste.conantorres.dev' \
     -l traefik.http.services.teste-dns01.loadbalancer.server.port=80 \
     "$WHOAMI"
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

## Próximos passos

Fora do escopo desta base, na ordem natural de estudo:

1. **Nuvem laranja da Cloudflare (proxy).** Os registros começam em "só DNS"
   (nuvem cinza), para o Traefik emitir certificados sem surpresa. Com tudo
   funcionando, ligar a nuvem laranja traz cache e proteção, mas exige: modo
   SSL/TLS "Full (strict)" na Cloudflare, confiar nos IPs da Cloudflare no
   Traefik (`forwardedHeaders.trustedIPs`, para o IP real do visitante nos
   logs) e lembrar que o desafio HTTP-01 só funciona se a porta 80 chegar ao
   Traefik. Vira uma issue quando o repositório for publicado.
2. **Grafana + Prometheus.** As métricas já estão ligadas em
   `http://traefik:8082/metrics` (rede `proxy`) e em `127.0.0.1:8082` (túnel
   SSH). Basta subir um Prometheus na rede `proxy` apontando para esse
   endereço e um Grafana lendo dele, sem publicar portas (acesso por túnel
   SSH). Painéis úteis: validade dos certificados
   (`traefik_tls_certs_not_after`, alertar com menos de 20 dias), requisições
   e erros 5xx por serviço (`traefik_service_requests_total`), e uptime dos sites (blackbox exporter batendo nos
   domínios por HTTPS).
3. Ler o [estudo de delegação DNS-01 por CNAME](#estudo-extra-delegação-do-dns-01-por-cname)
   para domínios sem API.
