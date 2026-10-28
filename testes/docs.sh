#!/usr/bin/env bash
# Verificação isolada da documentação (não sobe nada, não usa portas).
# Confere os critérios do README/guia: nomes do contrato, emissores,
# exemplo único, escopo do token e próximos passos.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
falhas=0
tem() { # arquivo padrão descrição
  if grep -qF -- "$2" "$1" 2>/dev/null; then
    echo "ok    $3"
  else
    echo "FALHA $3 ($1: $2)"
    falhas=$((falhas + 1))
  fi
}
nao_tem() { # arquivo padrão descrição
  if grep -qF -- "$2" "$1" 2>/dev/null; then
    echo "FALHA $3 ($1 ainda tem: $2)"
    falhas=$((falhas + 1))
  else
    echo "ok    $3"
  fi
}
tem_re() { # arquivo regex-estendida descrição
  if grep -qE -- "$2" "$1" 2>/dev/null; then
    echo "ok    $3"
  else
    echo "FALHA $3 ($1: /$2/)"
    falhas=$((falhas + 1))
  fi
}
# secao_readme "título" [fora]: imprime a seção "## título" do README (com "fora", o README sem ela).
secao_readme() {
  awk -v t="## $1" -v fora="${2:-}" '/^## /{on=($0 == t)} (fora == "") ? on : !on' README.md
}
G=docs/como-plugar-um-projeto.md
for n in web websecure proxy le-dns le-http 'seguranca@file' 'compressao@file' 'www-para-raiz@file'; do
  tem $G "$n" "guia lista $n"
done
tem $G 'tls.domains[0].sans=*.' "guia mostra labels do le-dns (curinga)"
tem $G 'tls.certresolver=le-http' "guia mostra labels do le-http"
tem $G 'exemplos/whoami/docker-compose.yml' "guia aponta o exemplo único"
tem $G 'read:packages' "guia cita token read:packages"
tem $G 'healthcheck' "guia exige healthcheck"
tem $G 'GitHub Actions' "guia cita deploy via Actions"
tem exemplos/whoami/docker-compose.yml '# healthcheck:' "exemplo traz bloco de healthcheck comentado"
tem README.md 'docker network create proxy' "README cria a rede proxy"
tem README.md '/opt/traefik' "README cita /opt/traefik"
tem README.md '/opt/apps/' "README cita /opt/apps"
tem README.md 'ufw allow 443' "README libera 443 no firewall"
tem README.md 'Fixar e atualizar a versão' "README explica fixar/atualizar Traefik"
tem README.md 'nuvem laranja' "README cita nuvem laranja"
tem README.md 'Grafana' "README cita Grafana"
tem README.md 'docs/como-plugar-um-projeto.md' "README linka o guia"
tem README.md 'Zone / Zone / Read' "README: escopo do token"
tem .env.example 'Zone / Zone / Read' ".env.example: escopo do token"
tem $G 'Zone / Zone / Read' "guia: escopo do token"
tem README.md '127.0.0.1:9100' "README cita a porta 9100 no loopback"
tem README.md '-L 9100:127.0.0.1:9100' "README: túnel para a 9100"
tem README.md 'prom/node-exporter:vX.Y.Z' "README: roteiro de versão cobre o node exporter"
tem README.md 'Monitoramento a partir de outra máquina' "README tem a seção de monitoramento remoto"
tem README.md '--shell /usr/sbin/nologin' "README cria metricas sem shell"
tem README.md '--disabled-password' "README cria metricas sem senha"
tem README.md 'restrict,port-forwarding,permitopen="127.0.0.1:8082",permitopen="127.0.0.1:9100",permitopen="127.0.0.1:3100"' "README: chave restrita às portas 8082, 9100 e 3100"
tem README.md 'AllowTcpForwarding' "README: conferir AllowTcpForwarding do sshd"
tem README.md 'sshd -T' "README: conferir a config efetiva do sshd"
tem README.md 'administratively prohibited' "README: teste manual da porta recusada"
tem README.md '../homelab-monitoring' "README linka o homelab-monitoring"
# Logs: Loki e Alloy na borda.
tem README.md '## Logs (Loki e Alloy)' "README: seção de logs"
tem README.md 'wget-loki' "README: serviço de uma vez que dá o wget ao healthcheck do Loki"
tem README.md 'docker compose logs socket-proxy' "README: log do socket-proxy fica fora do Loki"
tem alloy/config.alloy 'servico=\"socket-proxy\"' "Alloy descarta o ruído do socket-proxy"
nao_tem docker-compose.yml 'ferramentas' "compose sem o nome antigo (ferramentas)"
tem README.md '127.0.0.1:3100' "README cita a porta 3100 no loopback"
tem README.md '-L 3100:127.0.0.1:3100' "README: túnel para a 3100"
tem README.md '30 dias' "README: retenção de 30 dias"
tem README.md 'grafana/loki:X.Y.Z' "README: roteiro de versão cobre o Loki"
tem README.md 'grafana/alloy:vX.Y.Z' "README: roteiro de versão cobre o Alloy"
tem README.md 'Consulta de emergência na VPS' "README: consulta de emergência na VPS"
tem README.md 'RouterName' "README: rótulo router vem do RouterName"
tem .scratch/traefik-vps-base/SPEC.md 'primeiro armazenamento de monitoramento na VPS' "SPEC registra a exceção do Loki"
H=.scratch/traefik-vps-base/HANDOFF.md
nao_tem README.md 'Basta subir um Prometheus na rede' "próximos passos sem o plano antigo do Prometheus na rede proxy"
tem README.md '../homelab-monitoring#colocar-no-ar' "próximos passos aponta para colocar no ar do homelab-monitoring"
tem "$H" 'node exporter' "HANDOFF registra o node exporter"
tem "$H" 'metricas' "HANDOFF registra o usuário metricas"
tem "$H" 'concluído em 2026-10-27, com alertas no Telegram' "HANDOFF: item 2 concluído, com Telegram"
tem "$H" '127.0.0.1:9100' "HANDOFF cita a porta 9100 no loopback"
tem "$H" 'Loki' "HANDOFF registra o Loki na borda"
# Nuvem laranja: Traefik confia no X-Forwarded-For só vindo da Cloudflare.
tem traefik/traefik.yml 'trustedIPs' "traefik.yml: forwardedHeaders.trustedIPs nas entradas públicas"
tem traefik/traefik.yml '173.245.48.0/20' "traefik.yml: faixas IPv4 da Cloudflare"
tem traefik/traefik.yml '2400:cb00::/32' "traefik.yml: faixas IPv6 da Cloudflare"
tem README.md '## Nuvem laranja da Cloudflare' "README: seção da nuvem laranja"
tem README.md 'https://www.cloudflare.com/ips-v4' "README: de onde vêm as faixas da Cloudflare"
tem README.md 'Full (strict)' "README: modo SSL/TLS Full (strict)"
tem README.md 'loki_dados_bytes' "README: disco do Loki publicado pelo node exporter"
tem docker-compose.yml '--collector.textfile.directory=/textfile' "node exporter lê o textfile do disco do Loki"
# Dependabot: um PR mensal com as imagens da borda.
D=.github/dependabot.yml
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Cada entrada de update vai para um arquivo, para conferir uma de cada vez.
bloco() { # ecossistema -> arquivo com só aquela entrada
  awk -v e="$1" '/^  - package-ecosystem: /{on=($0 == "  - package-ecosystem: " e)} on' $D > "$tmp/$1"
  echo "$tmp/$1"
}
DC=$(bloco docker-compose)
tem_re $D '^  - package-ecosystem: docker-compose$' "Dependabot: ecossistema docker-compose"
tem_re $DC '^    directories:$' "Dependabot: docker-compose numa entrada só, com lista de diretórios (um PR por mês)"
tem_re $DC '^      - "/"$' "Dependabot: diretório / (compose principal)"
tem_re $DC '^      - "/exemplos/whoami"$' "Dependabot: diretório /exemplos/whoami"
nao_tem $DC '    directory:' "Dependabot: docker-compose sem entrada separada por diretório"
n=$(grep -cE '^  - package-ecosystem: docker-compose$' $D)
if [ "$n" = 1 ]; then echo "ok    Dependabot: uma única entrada de docker-compose"; else echo "FALHA Dependabot: esperada 1 entrada de docker-compose, há $n"; falhas=$((falhas + 1)); fi
n=$(grep -cE '^  - package-ecosystem:' $D)
if [ "$n" = 1 ]; then echo "ok    Dependabot: só a entrada das imagens (sem github-actions)"; else echo "FALHA Dependabot: esperada 1 entrada de update, há $n"; falhas=$((falhas + 1)); fi
nao_tem $D 'github-actions' "Dependabot: sem ecossistema github-actions"
tem $DC 'interval: monthly' "Dependabot: imagens com agenda mensal"
tem $DC 'default-days: 14' "Dependabot: imagens com cooldown de 14 dias"
tem $DC 'dependency-name: busybox' "Dependabot: regra do BusyBox"
tem $DC 'version-update:semver-minor' "Dependabot: BusyBox sem salto de linha (semver-minor ignorado)"
nao_tem $D 'open-pull-requests-limit: 0' "Dependabot: limite de PRs acima de 0"
# Sem deploy pelo CI: a borda não tem workflow nenhum (o deploy é só o cron).
if [ -n "$(ls .github/workflows 2>/dev/null)" ]; then echo "FALHA .github/workflows não deve ter arquivos (deploy só pelo cron)"; falhas=$((falhas + 1)); else echo "ok    .github/workflows vazio"; fi
tem README.md 'Insights → Dependency graph → Dependabot' "README: onde conferir a leitura do Dependabot"
tem README.md 'Atualização das imagens (Dependabot)' "README: item do Dependabot no checklist manual"
tem_re README.md 'Dependency graph → Dependabot que o GitHub leu' "README: checklist manual manda conferir o Dependency graph depois do merge"
tem README.md 'PR do Dependabot' "README: roteiro de revisão do PR do Dependabot"
tem README.md 'IMAGEM_LOKI' "README: aprovar PR do Loki atualiza o Loki falso do homelab (smoke.env)"
tem README.md 'Loki da borda:' "README: aprovar PR do Loki atualiza a nota de versão do homelab"
# Restos do deploy por SSH (descartado em 2026-10-28): nenhuma referência fora
# de .scratch (histórico) e deste arquivo.
# O README só pode citá-los no roteiro de limpeza ("Limpar o deploy por SSH").
sem_limpeza="$tmp/README-sem-limpeza"
secao_readme "Limpar o deploy por SSH" fora > "$sem_limpeza"
for padrao in deploy-vps .deploy-pelo-ci; do
  restos=$(grep -rIlF --exclude-dir=.git --exclude-dir=.scratch --exclude=docs.sh --exclude=README.md -- "$padrao" . 2>/dev/null)
  grep -qF -- "$padrao" "$sem_limpeza" && restos="$restos README.md"
  if [ -z "$restos" ]; then echo "ok    nenhuma referência a $padrao"; else echo "FALHA referência a $padrao em: $restos"; falhas=$((falhas + 1)); fi
done
nao_tem README.md '## Deploy pelo CI' "README: sem a seção Deploy pelo CI"
nao_tem README.md 'Checklist do primeiro deploy' "README: sem o checklist do primeiro deploy"
nao_tem $G 'Pelo CI' "guia: sem deploy pelo CI"
tem $G '**Pelo cron.**' "guia: cron como caminho de deploy"
tem $G '**Manual' "guia: deploy manual"
# Roteiro para o dono limpar a VPS e o GitHub.
tem README.md '## Limpar o deploy por SSH' "README: seção do roteiro de limpeza"
tem README.md 'sudo rm /etc/sudoers.d/deploy' "limpeza: remove o sudoers do deploy"
tem README.md 'sudo visudo -c' "limpeza: valida o sudoers com visudo -c"
tem README.md 'sudo deluser --remove-home deploy' "limpeza: remove o usuário deploy"
tem README.md 'sudo rm /usr/local/sbin/' "limpeza: apaga o script instalado"
tem README.md 'sudo install -m 755 /opt/traefik/vps/atualizar-apps.sh' "limpeza: reinstala o script do cron"
tem README.md 'gh api -X DELETE repos/C0nanT/traefik-default/environments/producao' "limpeza: apaga o Environment producao da borda"
tem README.md 'gh api -X DELETE repos/C0nanT/conantorres.dev/environments/producao' "limpeza: apaga o Environment producao do site"
# Log do cron no Loki (ticket 03).
tem alloy/config.alloy 'loki.source.file "atualizar_apps"' "Alloy lê o log do cron (loki.source.file)"
tem_re alloy/config.alloy 'job +=  *"atualizar-apps"' "Alloy rotula o log do cron com job=atualizar-apps"
tem docker-compose.yml '${LOG_CRON_DIR:-/var/log/atualizar-apps}:/log-host:ro' "compose monta só a pasta dedicada do log do cron, só leitura"
nao_tem docker-compose.yml '${LOG_CRON_DIR:-/var/log}:' "compose não monta /var/log inteiro"
tem vps/atualizar-apps.logrotate '/var/log/atualizar-apps/atualizar-apps.log {' "logrotate: caminho na pasta dedicada"
tem vps/atualizar-apps.logrotate 'delaycompress' "logrotate: delaycompress (o Alloy termina o arquivo rotacionado)"
tem vps/atualizar-apps.sh 'mkdir -p' "script cria a pasta do log se faltar"
tem README.md 'sudo install -d -m 755 /var/log/atualizar-apps' "README: migração única cria a pasta do log"
tem README.md 'sudo install -m 644 /opt/traefik/vps/atualizar-apps.cron' "README: migração reinstala o cron.d"
tem vps/atualizar-apps.logrotate 'create 0644 root root' "logrotate recria o log legível pelo Alloy"
tem README.md '{job="atualizar-apps"}' "README: consulta LogQL do log do cron"
tem testes/verificacoes/08-log-cron.sh 'job=atualizar-apps' "smoke confere a linha do cron no Loki com o rótulo"
# Checklist manual da falha forçada: os passos ficam só nessa seção.
falha_forcada="$tmp/README-falha-forcada"
secao_readme "Checklist manual da falha forçada" > "$falha_forcada"
tem "$falha_forcada" 'cd /opt/traefik && git pull' "checklist da falha: git pull em /opt/traefik"
tem "$falha_forcada" 'sudo install -m 755 /opt/traefik/vps/atualizar-apps.sh /usr/local/bin/atualizar-apps.sh' "checklist da falha: reinstala o script do cron"
tem "$falha_forcada" 'sudo install -m 644 /opt/traefik/vps/atualizar-apps.logrotate /etc/logrotate.d/atualizar-apps' "checklist da falha: reinstala o logrotate do cron"
tem "$falha_forcada" 'docker compose up -d' "checklist da falha: sobe a borda para o Alloy pegar o volume"
tem "$falha_forcada" 'docker compose ps alloy' "checklist da falha: confere o Alloy"
tem "$falha_forcada" 'deploy_falhou' "checklist da falha: série deploy_falhou"
tem "$falha_forcada" 'deploy_rodada_timestamp_seconds' "checklist da falha: série da hora da rodada"
tem "$falha_forcada" 'Deploy (cron)' "checklist da falha: linha Deploy (cron) do painel"
tem "$falha_forcada" 'IMAGE_TAG=tag-que-nao-existe' "checklist da falha: força a falha com IMAGE_TAG inválida"
tem "$falha_forcada" 'Deploy falhou (VPS)' "checklist da falha: alerta de falha no Telegram"
tem "$falha_forcada" 'Cron de deploy parado' "checklist da falha: alerta de cron parado (opcional)"
tem "$falha_forcada" 'sudo install -m 644 /opt/traefik/vps/atualizar-apps.cron /etc/cron.d/atualizar-apps' "checklist da falha: religa o cron"
tem "$falha_forcada" 'resolvido' "checklist da falha: confere o alerta resolvido"
tem README.md '[Checklist da falha forçada](#checklist-manual-da-falha-forçada)' "README: índice aponta o checklist da falha forçada"
# Acesso à VPS pelo apelido `ssh vps` (README).
# Fora desta conferência ficam os exemplos do túnel de métricas
# (metricas@IP_DA_VPS, chave id_tunel): rodam no homelab, com outro usuário e outra chave.
acesso="$tmp/README-acesso-vps"
secao_readme "Acesso à VPS (ssh vps)" > "$acesso"
tem README.md '`ssh vps`' "README: ponteiro para o apelido ssh vps"
tem README.md '(#acesso-à-vps-ssh-vps)' "README: ponteiro aponta o bloco Host vps"
topo="$tmp/README-topo"
head -n 12 README.md > "$topo"
tem "$topo" 'ssh vps' "README: ponteiro ssh vps perto do topo (primeiras 12 linhas)"
tem "$acesso" 'Host vps' "acesso: bloco Host vps"
tem_re "$acesso" '^ +HostName IP_DA_VPS$' "acesso: HostName com o placeholder IP_DA_VPS"
tem_re "$acesso" '^ +User root$' "acesso: User root"
tem_re "$acesso" '^ +IdentityFile ~/\.ssh/id_ed25519$' "acesso: IdentityFile da chave"
tem_re "$acesso" '^ +IdentitiesOnly yes$' "acesso: IdentitiesOnly"
tem_re "$acesso" '^ +PasswordAuthentication no$' "acesso: só chave, sem senha"
tem_re "$acesso" '^ +StrictHostKeyChecking accept-new$' "acesso: confere a chave do servidor"
tem "$acesso" 'só comandos de leitura' "acesso: regra de só leitura para o agente"
tem "$acesso" 'rodada pelo dono' "acesso: mudanças na VPS são rodadas pelo dono"
# Nenhum exemplo de comando usa o IP direto: falha com qualquer @IP_DA_VPS ou ssh ... IP_DA_VPS,
# exceto o túnel de métricas (metricas@IP_DA_VPS) e a linha `HostName IP_DA_VPS` do bloco.
ip_direto=$(grep -nE '@IP_DA_VPS|ssh .*IP_DA_VPS' README.md | grep -vF 'metricas@IP_DA_VPS' | grep -vE 'HostName IP_DA_VPS' || true)
if [ -z "$ip_direto" ]; then
  echo "ok    README: nenhum exemplo de acesso usa o IP direto"
else
  echo "FALHA README: exemplo com IP direto (fora o túnel metricas@IP_DA_VPS): $ip_direto"
  falhas=$((falhas + 1))
fi
tem README.md 'ssh -N -L 8080:127.0.0.1:8080 -L 8082:127.0.0.1:8082 -L 9100:127.0.0.1:9100 -L 3100:127.0.0.1:3100 vps' "README: túnel do painel usa ssh vps"
tem README.md 'metricas@IP_DA_VPS' "README: túnel de métricas mantém metricas@IP_DA_VPS"
# Hook de pre-commit: versionado, executável, roda os dois testes rápidos e o README ensina a ativar.
H=.githooks/pre-commit
if [ -x "$H" ]; then echo "ok    hook de pre-commit existe e é executável"; else echo "FALHA hook de pre-commit ausente ou sem permissão de execução ($H)"; falhas=$((falhas + 1)); fi
tem "$H" 'testes/docs.sh' "hook roda o docs.sh"
tem "$H" 'testes/deploy.sh' "hook roda o deploy.sh"
nao_tem "$H" 'smoke.sh' "hook não roda o smoke (sobe a borda inteira)"
tem README.md 'git config core.hooksPath .githooks' "README: comando que ativa o hook"
tem README.md '--no-verify' "README: como pular o hook"
exit $((falhas > 0))
