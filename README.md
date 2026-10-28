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
[Logs](#logs-loki-e-alloy) ·
[Deploy pelo CI](#deploy-pelo-ci-usuário-deploy) ·
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
   e erros em `/var/log/atualizar-apps.log`, com rotação semanal. Pasta que
   tiver o arquivo-marcador `.deploy-pelo-ci` é pulada pelo cron (quem
   atualiza é o deploy pelo CI):
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
docker compose ps     # traefik, socket-proxy, node-exporter, loki e alloy (healthy)
docker compose ps -a wget-loki   # roda uma vez e sai: "Exited (0)"
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
  `tecnativa/docker-socket-proxy:vX.Y.Z`, `prom/node-exporter:vX.Y.Z`,
  `grafana/loki:X.Y.Z` (sem o "v"), `grafana/alloy:vX.Y.Z` e
  `busybox:X.Y.Z-musl` (só o wget do healthcheck do Loki);
- `exemplos/whoami/docker-compose.yml`: `traefik/whoami:vX.Y.Z` (app de
  exemplo e do smoke test).

O smoke test não repete nenhuma delas: usa a imagem do Traefik do container
em execução e lê a do whoami do exemplo.

O caminho normal é o **PR do Dependabot**: uma vez por mês ele abre um PR
com as imagens que tiveram versão nova, só com versões publicadas há pelo
menos 14 dias (config em `.github/dependabot.yml`). Duas regras do BusyBox:
o Dependabot mantém o sufixo `-musl` e, como o `ignore` não aceita curinga
para barrar as versões `X.Y.0` (instáveis), só propõe patches da linha
atual; subir de linha (1.36 para 1.37) é à mão, com um `X.Y.1` ou
posterior. Para revisar e aplicar o PR do Dependabot:

1. Leia as notas de versão que o PR mostra (e o "upgrade guide" do Loki).
2. No seu computador, pegue a branch do PR e rode `testes/smoke.sh`.
3. Aprove e mescle o PR (nada é mesclado sozinho).
4. Na VPS: `git pull` e `docker compose up -d` (com `pull` antes, como no
   passo 3 do roteiro à mão abaixo).
5. Depois do primeiro merge da configuração, confira se o GitHub a leu sem
   erro em
   Insights → Dependency graph → Dependabot.

O Loki falso do smoke do `homelab-monitoring` repete a tag do Loki daqui, e
o Dependabot de lá não o enxerga. Ao aprovar um PR do Loki, atualize no
`homelab-monitoring`, junto: o `IMAGEM_LOKI` do `testes/smoke.env` e a nota
"Loki da borda:" do README (o `testes/docs.sh` de lá falha se divergirem).

O roteiro à mão continua valendo, a qualquer momento (correção urgente).
Para atualizar, de propósito:

1. Leia as notas de versão do Traefik
   (<https://github.com/traefik/traefik/releases>), sobretudo em mudança de
   versão maior/menor. Para o node exporter, as de
   <https://github.com/prometheus/node_exporter/releases> (nomes de métricas
   podem mudar e quebrar painéis/alertas do Grafana). Para o Loki e o
   Alloy, <https://github.com/grafana/loki/releases> e
   <https://github.com/grafana/alloy/releases> (o Loki muda formato de
   armazenamento e opções entre versões menores; leia o "upgrade guide").
2. Teste antes: no seu computador, troque a tag em `docker-compose.yml`
   (só ali) e rode `testes/smoke.sh` (usa as portas 80/443 e
   127.0.0.1:8080/8082/9100/3100 da máquina; não rode na VPS com a pilha de
   pé).
3. Na VPS, troque a tag em `docker-compose.yml` (commit + pull, ou edição
   direta) e então:
   ```bash
   docker compose pull
   docker compose up -d
   docker compose ps && docker compose logs --tail 50 traefik
   docker compose logs --tail 50 node-exporter   # se trocou essa tag
   docker compose logs --tail 50 loki alloy      # se trocou essas tags
   ```
4. Para voltar atrás, restaure a tag anterior e repita o `up -d`. Faça
   backup de `acme/` antes de atualizar.

Os arquivos de `acme/` e o `.env` ficam fora do controle de versão e
sobrevivem à troca de imagem. Os logs guardados ficam no volume
`traefik_loki-dados` e também sobrevivem (só `docker compose down -v` os
apaga).

## Painel e métricas via túnel SSH

O painel/API do Traefik (porta 8080), as métricas Prometheus do Traefik
(porta 8082) e as do host, pelo node exporter (porta 9100), **não** são
acessíveis pela internet: nunca respondem em 80/443. O `docker-compose.yml`
publica essas três portas apenas no loopback da VPS (`127.0.0.1:8080`,
`127.0.0.1:8082` e `127.0.0.1:9100`), então só se chega a elas de dentro do
servidor, por um túnel SSH.

No seu computador:

```bash
ssh -N -L 8080:127.0.0.1:8080 -L 8082:127.0.0.1:8082 -L 9100:127.0.0.1:9100 -L 3100:127.0.0.1:3100 usuario@IP_DA_VPS
```

Com o túnel aberto, no seu navegador/terminal:

- Painel: <http://localhost:8080/dashboard/> (a barra final é obrigatória)
- API: <http://localhost:8080/api/overview>
- Métricas do Traefik: <http://localhost:8082/metrics>
- Métricas do host (node exporter): <http://localhost:9100/metrics>
- Loki (logs): <http://localhost:3100/ready> (consultas: veja
  [Logs](#logs-loki-e-alloy))

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
(ex.: um Prometheus nessa rede) alcançam `http://traefik:8082/metrics`, sem passar
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

Esse histórico é curto e some quando o container é recriado. O que fica
guardado por 30 dias está no Loki (próxima seção).

## Logs (Loki e Alloy)

A borda guarda os logs de **todos** os containers da VPS (os sites e a
própria borda) por **30 dias**, para o Grafana do
[`homelab-monitoring`](../homelab-monitoring) consultar pelo túnel SSH:

- **Alloy** (`grafana/alloy`, configuração em `alloy/config.alloy`): descobre
  os containers e lê os logs pela API do Docker, **só leitura**, pelo
  `docker-socket-proxy` (o socket nunca é montado nele). Site novo plugado na
  borda entra sozinho, sem configuração. Lê em tempo real, antes de a
  rotação do Docker descartar a linha; recriar um container (deploy) não
  apaga o que já foi coletado. **Exceção:** o log do `socket-proxy` é
  descartado no Alloy (`stage.match` com `action = "drop"`): ele registra
  cada consulta do Alloy à API do Docker e encheria o Loki de ruído por 30
  dias. Os 403 do proxy também ficam de fora; veja-os com
  `docker compose logs socket-proxy`.
- **Loki** (`grafana/loki`, configuração em `loki/loki.yml`): guarda os
  logs no volume `loki-dados`, publicado **só** em `127.0.0.1:3100`, numa
  rede própria (`logs`), fora da rede `proxy`: nenhum site o alcança. Sem
  autenticação; a proteção é o loopback mais o túnel restrito, como nas
  métricas. A imagem não tem shell nem `wget`: o serviço de uma vez
  `wget-loki` (BusyBox) copia um `wget` para o volume `wget-loki`, usado
  pelo healthcheck.
- **Disco do Loki** (`disco-loki`, script em `loki/medir-disco.sh`): BusyBox
  sem rede que mede o volume `loki-dados` (só leitura) a cada 5 min e grava
  `loki_dados_bytes` no volume `textfile`. O node exporter publica a série
  (textfile collector) junto com as do host, então ela chega ao homelab
  pelo mesmo túnel da 9100: nenhuma porta nova.
- Loki, Alloy, `wget-loki`, `disco-loki` e o `socket-proxy` têm a mesma rotação de log do
  Docker que o Traefik (5 arquivos de 10 MB).

Por que um armazenamento na VPS (até aqui só iam exporters leves): o log
nasce aqui e, guardado no PC, se perderia com o PC desligado. É uma
exceção consciente, registrada na SPEC.

**Rótulos** (poucos e de baixa cardinalidade; o resto fica no corpo da
linha e sai na consulta com `| json`):

| Rótulo | Valores | De onde vem |
|---|---|---|
| `projeto` | `traefik`, `conan-torres`, `bbcontainer`... | projeto do compose |
| `servico` | `traefik`, `web`, `app`, `loki`... | serviço do compose |
| `stream` | `stdout`, `stderr` | saída do container |
| `tipo` | `acesso`, `traefik` | só nas linhas do Traefik: JSON de acesso ou log próprio |
| `router` | ex.: `conan-torres@docker` | só nas linhas de acesso, do campo `RouterName` |

O `router` vem do `RouterName` (os routers configurados, um conjunto
fechado), **nunca** do `RequestHost`: o Host vem do cliente, e bots mandando
qualquer Host criariam um stream novo por valor. Requisição que não casou
com nenhum router (404 da borda) fica sem `router`.

**Limites** (`loki/loki.yml`): taxa de entrada e rajada (total e por
stream), teto de streams e tamanho de linha. Numa enxurrada (varredura de
bots), o excesso é recusado em vez de encher o disco. E com o disco do host
acima de 90% o Loki recusa linhas novas. Memória: 512 MB no Loki e 256 MB
no Alloy (`mem_limit`). Uso de disco: painel **Logs** do Grafana (disco do Loki e
do host, com a linha dos 90%) ou `docker system df -v | grep loki-dados`.

**Porta 3100 para o `metricas`.** O Grafana lê o Loki pelo mesmo túnel das
métricas. A linha do `authorized_keys` do `metricas` precisa de
`permitopen="127.0.0.1:3100"` (já está no passo 2 de
[Monitoramento a partir de outra máquina](#monitoramento-a-partir-de-outra-máquina)).
Quem já tinha a linha antiga, na VPS:

```bash
sudo sed -i 's|permitopen="127.0.0.1:9100"|permitopen="127.0.0.1:9100",permitopen="127.0.0.1:3100"|' \
  /home/metricas/.ssh/authorized_keys
sudo cat /home/metricas/.ssh/authorized_keys   # confira a linha
```

O `sshd` lê o arquivo a cada conexão: basta o túnel reconectar.

### Consulta de emergência na VPS

Sem o PC, direto na VPS (o Loki responde no loopback), com `curl`. A
consulta é LogQL; `since` é o período:

```bash
# Estado do Loki
curl -s http://127.0.0.1:3100/ready
# Quais projetos têm logs
curl -s http://127.0.0.1:3100/loki/api/v1/label/projeto/values
# Últimas 50 linhas do stderr do conan-torres na última hora
curl -s -G http://127.0.0.1:3100/loki/api/v1/query_range \
  --data-urlencode 'query={projeto="conan-torres", stream="stderr"}' \
  --data-urlencode 'since=1h' --data-urlencode 'limit=50' \
  | python3 -c 'import json,sys; [print(l) for r in json.load(sys.stdin)["data"]["result"] for _, l in r["values"]]'
# Respostas 5xx do log de acesso nas últimas 6 horas
curl -s -G http://127.0.0.1:3100/loki/api/v1/query_range \
  --data-urlencode 'query={tipo="acesso"} | json | DownstreamStatus >= 500' \
  --data-urlencode 'since=6h' --data-urlencode 'limit=50'
```

Se o Loki estiver fora, o log curto do Docker continua lá:
`docker compose logs` em `/opt/traefik` ou na pasta do site.

## Monitoramento a partir de outra máquina

O [`homelab-monitoring`](../homelab-monitoring) (Prometheus + Grafana) roda
**no meu PC**, não na VPS, e coleta as métricas do Traefik (`127.0.0.1:8082`)
e do node exporter (`127.0.0.1:9100`), e consulta os logs no Loki
(`127.0.0.1:3100`), por um túnel SSH permanente. Esse túnel usa um usuário
próprio, `metricas`, sem shell e sem senha, cuja chave **só** pode abrir
túnel para essas três portas do loopback. Se a chave vazar, dá para ler
métricas e logs e nada mais: nem shell, nem o painel (8080), nem outra
porta.
Nada novo é publicado na internet.

Na VPS, uma vez:

1. Crie o usuário, sem shell e sem senha:
   ```bash
   sudo adduser --disabled-password --gecos "" --shell /usr/sbin/nologin metricas
   ```
2. Coloque a chave pública gerada no PC (`chaves/id_tunel.pub` do
   `homelab-monitoring`) com as restrições na frente, numa linha só:
   ```bash
   sudo install -d -m 700 -o metricas -g metricas /home/metricas/.ssh
   echo 'restrict,port-forwarding,permitopen="127.0.0.1:8082",permitopen="127.0.0.1:9100",permitopen="127.0.0.1:3100" ssh-ed25519 AAAA...COLE_A_CHAVE... metricas@homelab' \
     | sudo tee /home/metricas/.ssh/authorized_keys >/dev/null
   sudo chown metricas:metricas /home/metricas/.ssh/authorized_keys
   sudo chmod 600 /home/metricas/.ssh/authorized_keys
   ```
   `restrict` desliga tudo (terminal, agente, X11, encaminhamentos);
   `port-forwarding` religa só o encaminhamento local, e os `permitopen`
   limitam o destino a essas três portas.
3. Confira a configuração **efetiva** do `sshd` para o `metricas` (inclui
   `/etc/ssh/sshd_config.d/`; o `-C` aplica também os blocos `Match`):
   ```bash
   sudo sshd -T -C user=metricas,host=pc,addr=IP_DO_PC \
     | grep -iE '^(allowtcpforwarding|disableforwarding|permitopen|allowusers|allowgroups|usepam) '
   ```
   - `AllowTcpForwarding` precisa ser `yes` ou `local` (com `no`, o túnel
     é recusado);
   - `DisableForwarding` precisa ser `no` (com `yes`, ele vence o
     `AllowTcpForwarding` e o túnel é recusado);
   - `permitopen` precisa ser `any` (ou incluir as três portas);
   - se existir `allowusers`/`allowgroups`, o `metricas` precisa estar na
     lista, senão o login é recusado sem aviso claro;
   - `usepam yes` (padrão do Ubuntu): com ele, a conta sem senha entra por
     chave normalmente.

   Se precisar mudar, crie um arquivo em `/etc/ssh/sshd_config.d/`, teste
   com `sudo sshd -t` e aplique com `sudo systemctl reload ssh`.
4. Teste do PC (manual, uma vez), com a chave do `metricas`:
   ```bash
   # Shell recusado: "This account is currently not available." (ou fecha na hora)
   ssh -i chaves/id_tunel -o IdentitiesOnly=yes metricas@IP_DA_VPS
   # Porta permitida: deve responder com métricas
   ssh -i chaves/id_tunel -o IdentitiesOnly=yes -N -L 18082:127.0.0.1:8082 metricas@IP_DA_VPS &
   sleep 3; curl -s http://localhost:18082/metrics | head -3; kill %1
   # Porta NÃO permitida (o painel, 8080): o ssh mostra
   # "channel N: open failed: administratively prohibited" e o curl falha
   ssh -i chaves/id_tunel -o IdentitiesOnly=yes -N -L 18080:127.0.0.1:8080 metricas@IP_DA_VPS &
   sleep 3; curl -s http://localhost:18080/api/overview; kill %1
   ```

O resto (gerar a chave, pegar o `known_hosts` da VPS, preencher o `.env` e
subir o túnel em container) está em "Túnel até a VPS" no README do
[`homelab-monitoring`](../homelab-monitoring). Para revogar o acesso, apague
a linha do `authorized_keys` (ou `sudo deluser --remove-home metricas`).

## Deploy pelo CI (usuário `deploy`)

O GitHub Actions faz o deploy entrando na VPS por SSH com um usuário
próprio, `deploy`. Ele não está no grupo `docker` e não tem terminal, túnel
nem comando livre: cada chave só consegue rodar
`sudo /usr/local/sbin/deploy-vps <projeto>`, com o projeto fixado na linha
do `authorized_keys`. O único dado que vem do GitHub é o SHA do commit, e o
script confere que são 40 caracteres hexadecimais antes de usar. Há uma
chave por repositório: a do `conan-torres` só faz deploy do site, a do
`traefik-default` só faz deploy da borda. Se uma chave vazar, dá para
disparar o deploy daquele projeto (até a ponta da `main`) e nada mais.

O script roda como root pelo sudo, então o `docker compose pull` usa o
`docker login ghcr.io` do root, o mesmo do cron. Não precisa de login novo.

Na VPS, uma vez:

1. Instale o script como root (repita depois de cada mudança em
   `vps/deploy-vps.sh`; o deploy da borda atualiza `/opt/traefik`, mas não
   reinstala o script):
   ```bash
   sudo install -m 755 -o root -g root /opt/traefik/vps/deploy-vps.sh /usr/local/sbin/deploy-vps
   ```
2. Crie o usuário, sem senha e **fora** do grupo `docker`:
   ```bash
   sudo adduser --disabled-password --gecos "" --shell /bin/sh deploy
   id deploy   # só o grupo deploy; nada de docker nem sudo
   ```
   O shell precisa ser real (`/bin/sh`): o `sshd` roda o comando forçado
   pelo shell do usuário, e com `nologin` nada roda. Quem restringe é o
   `restrict` + `command=` do passo 4, não o shell.
3. Libere no sudoers só o script, só com os dois argumentos permitidos. O
   `env_reset` padrão do sudo apaga o ambiente; o `env_keep` deixa passar só
   o `SSH_ORIGINAL_COMMAND`, onde chega o SHA. Valide antes de instalar (um
   sudoers quebrado trava o sudo de todo mundo):
   ```bash
   cat > /tmp/deploy-vps.sudoers <<'FIM'
   Defaults!/usr/local/sbin/deploy-vps env_keep += "SSH_ORIGINAL_COMMAND"
   deploy ALL=(root) NOPASSWD: /usr/local/sbin/deploy-vps conan-torres, /usr/local/sbin/deploy-vps traefik
   FIM
   sudo visudo -cf /tmp/deploy-vps.sudoers \
     && sudo install -m 440 -o root -g root /tmp/deploy-vps.sudoers /etc/sudoers.d/deploy-vps
   rm /tmp/deploy-vps.sudoers
   sudo -l -U deploy   # deve listar só as duas linhas do deploy-vps
   ```
4. Gere **no seu PC** uma chave ed25519 por repositório, sem senha (o
   Actions não tem como digitar), fora de qualquer repositório:
   ```bash
   ssh-keygen -t ed25519 -N "" -C deploy@conan-torres -f ~/.ssh/deploy-conan-torres
   ssh-keygen -t ed25519 -N "" -C deploy@traefik-default -f ~/.ssh/deploy-traefik-default
   ```
   A parte privada vai **só** para o secret do GitHub (passo 6); nunca para
   um commit. Na VPS entram as públicas (`.pub`), uma por linha, cada uma com
   o projeto fixado:
   ```bash
   sudo install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
   sudo tee /home/deploy/.ssh/authorized_keys >/dev/null <<'FIM'
   restrict,command="sudo /usr/local/sbin/deploy-vps conan-torres" ssh-ed25519 AAAA...CHAVE_DO_CONAN_TORRES... deploy@conan-torres
   restrict,command="sudo /usr/local/sbin/deploy-vps traefik" ssh-ed25519 AAAA...CHAVE_DO_TRAEFIK_DEFAULT... deploy@traefik-default
   FIM
   sudo chown deploy:deploy /home/deploy/.ssh/authorized_keys
   sudo chmod 600 /home/deploy/.ssh/authorized_keys
   ```
   `restrict` desliga terminal, agente, X11 e encaminhamentos; `command=`
   troca qualquer comando pedido pelo deploy-vps daquele projeto (o que o
   cliente pediu fica em `SSH_ORIGINAL_COMMAND`). Se existir `AllowUsers` ou
   `AllowGroups` no `sshd`, inclua o `deploy` (confira com
   `sudo sshd -T -C user=deploy,host=github,addr=1.2.3.4 | grep -iE '^allow(users|groups) '`).
5. Gere o `known_hosts` **no seu PC** e confira a impressão digital com a
   que a própria VPS mostra (assim o GitHub não manda a chave para uma
   máquina falsa):
   ```bash
   # No PC:
   ssh-keyscan -t ed25519 IP_DA_VPS > known_hosts-vps
   ssh-keygen -lf known_hosts-vps
   # Na VPS (por uma sessão que você já confia):
   ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
   ```
   Os dois `SHA256:...` precisam ser iguais. Se forem diferentes, pare.
6. Em **cada** repositório (`conan-torres` e `traefik-default`), crie o
   Environment `producao` limitado à `main`: Settings → Environments → New
   environment → `producao` → Deployment branches and tags →
   `Selected branches and tags` → Add rule → `main`. Depois os secrets, **do
   Environment** (não do repositório), cada repositório com a própria chave:

   | Secret            | Conteúdo                                                   |
   |-------------------|------------------------------------------------------------|
   | `VPS_HOST`        | IP (ou nome) da VPS, o mesmo usado no `ssh-keyscan`         |
   | `VPS_SSH_KEY`     | a chave **privada** daquele repositório                     |
   | `VPS_KNOWN_HOSTS` | o conteúdo de `known_hosts-vps` conferido no passo 5        |

   Pelo `gh`, sem colar a chave em lugar nenhum. Primeiro o site; depois
   repita com `R=C0nanT/traefik-default; K=~/.ssh/deploy-traefik-default`:
   ```bash
   R=C0nanT/conantorres.dev; K=~/.ssh/deploy-conan-torres
   gh secret set VPS_HOST --env producao -R "$R" --body IP_DA_VPS
   gh secret set VPS_SSH_KEY --env producao -R "$R" < "$K"
   gh secret set VPS_KNOWN_HOSTS --env producao -R "$R" < known_hosts-vps
   ```
   O usuário `deploy` é fixo nos workflows e não vira secret.
7. Teste a restrição do PC (manual, uma vez), **só com a chave do
   `conan-torres`** (a do `traefik-default` dispara o deploy da borda de
   verdade):
   ```bash
   # Comando livre vira o deploy-vps, que recusa: "ERRO: SHA inválido ..."
   ssh -i ~/.ssh/deploy-conan-torres -o IdentitiesOnly=yes deploy@IP_DA_VPS id
   # Túnel recusado: "administratively prohibited" e o curl falha
   ssh -i ~/.ssh/deploy-conan-torres -o IdentitiesOnly=yes -N -L 18082:127.0.0.1:8082 deploy@IP_DA_VPS &
   sleep 3; curl -s http://localhost:18082/metrics | head -3; kill %1
   ```
8. Depois do teste, apague as chaves privadas e o `known_hosts-vps` do PC
   (`rm ~/.ssh/deploy-conan-torres ~/.ssh/deploy-traefik-default known_hosts-vps`);
   a privada fica só no secret. Se precisar de novo, gere outra e troque a
   linha do `authorized_keys` e o secret.

Para revogar o acesso de um repositório, apague a linha dele no
`authorized_keys` (ou `sudo deluser --remove-home deploy` para todos) e o
secret `VPS_SSH_KEY` do Environment.

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

**Atualização das imagens (Dependabot)**
- [ ] Depois do merge da configuração, conferir em
      Insights → Dependency graph → Dependabot que o GitHub leu o
      `.github/dependabot.yml` sem erro e lista os dois diretórios (`/` e
      `/exemplos/whoami`).

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

## Nuvem laranja da Cloudflare

Com a nuvem **laranja** (proxy), o visitante fala com a Cloudflare e a
Cloudflare fala com a VPS. Isso traz cache e proteção, mas muda três coisas:

- **IP do visitante.** A conexão chega de um IP da Cloudflare; o visitante vem
  no cabeçalho `X-Forwarded-For`. O Traefik só aceita esse cabeçalho vindo das
  faixas oficiais da Cloudflare (`forwardedHeaders.trustedIPs` nas entradas
  `web` e `websecure`, em `traefik/traefik.yml`); de qualquer outra origem ele
  é descartado, para ninguém falsificar o IP no log. O smoke test confere
  isso (`testes/verificacoes/04-logs-e-metricas.sh`). O painel não muda: ele
  filtra pela origem da conexão, não pelo cabeçalho.
- **SSL/TLS.** A zona precisa estar em **Full (strict)**: a Cloudflare fala
  HTTPS com a VPS e valida o certificado do Let's Encrypt. Em "Flexible" ela
  fala HTTP, o Traefik redireciona para HTTPS e o site entra em loop de
  redirecionamento.
- **Certificado visto de fora.** O visitante (e o blackbox do
  `homelab-monitoring`) passa a ver o certificado da Cloudflare, não o do
  Let's Encrypt. Quem vigia a validade do certificado da VPS é o alerta pelo
  Traefik (`traefik_tls_certs_not_after`), que lê o certificado de dentro.

Só vale para zonas na Cloudflare (`conantorres.dev`). O DNS-01 (`le-dns`) não
é afetado. Não use HTTP-01 (`le-http`) atrás da nuvem laranja: em Full
(strict) a Cloudflare fala com a VPS pela 443, e o desafio, que o Traefik
responde na porta 80, não chega. Em zonas da Cloudflare, use o `le-dns`.

**Ligar, nesta ordem:**

1. A VPS já está com a lista de IPs confiáveis (`git pull` e
   `docker compose up -d --force-recreate traefik` em `/opt/traefik`).
2. Na Cloudflare, em *SSL/TLS → Overview*, escolha **Full (strict)**. Com a
   nuvem ainda cinza nada muda; confira que o site segue abrindo.
3. Em *DNS → Records*, ligue a nuvem laranja (*Proxied*) no registro do
   domínio e no `www`.
4. Confira de fora: `curl -sI https://conantorres.dev` responde `200` com
   `server: cloudflare`. Na VPS, o log mostra o **seu** IP, não um da
   Cloudflare:
   ```bash
   docker compose logs --since 2m traefik | grep '"RequestHost":"conantorres.dev"' | tail -n 1 | grep -o '"ClientHost":"[^"]*"'
   ```

**Voltar atrás:** desligue a nuvem (cinza) no DNS. A lista de IPs confiáveis
pode ficar; com a nuvem cinza ela não faz nada.

**Atualizar as faixas.** A Cloudflare publica as faixas em
<https://www.cloudflare.com/ips-v4> e <https://www.cloudflare.com/ips-v6>.
Elas mudam raramente; confira de vez em quando e, se mudarem, troque a lista
em `traefik/traefik.yml` e recrie o Traefik. Faixa faltando significa log com
IP da Cloudflare para quem passar por ela, não site fora do ar.

## Próximos passos

Fora do escopo desta base, na ordem natural de estudo:

1. **Firewall só para a Cloudflare (opcional).** A nuvem laranja está ligada
   no `conantorres.dev` desde 2026-10-27 (veja
   [Nuvem laranja da Cloudflare](#nuvem-laranja-da-cloudflare)). Dá para
   aceitar 80/443 no `ufw` só das faixas da Cloudflare, mas o
   `bbcontainermodular.com` não passa pela Cloudflare e precisa delas
   abertas, então isso exige regras por destino ou fica de fora.
2. **Grafana + Prometheus.** Ficam no
   [`homelab-monitoring`](../homelab-monitoring), que roda no meu PC (não na
   VPS) e coleta as métricas do Traefik e do node exporter por um túnel SSH
   com o usuário `metricas` (veja
   [Monitoramento a partir de outra máquina](#monitoramento-a-partir-de-outra-máquina)).
   Painéis e alertas no Telegram estão lá; a ordem para subir
   tudo está em
   ["Colocar no ar"](../homelab-monitoring#colocar-no-ar).
3. Ler o [estudo de delegação DNS-01 por CNAME](#estudo-extra-delegação-do-dns-01-por-cname)
   para domínios sem API.
