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
tem $H 'node exporter' "HANDOFF registra o node exporter"
tem $H 'metricas' "HANDOFF registra o usuário metricas"
tem $H 'concluído em 2026-10-27, com alertas no Telegram' "HANDOFF: item 2 concluído, com Telegram"
tem $H '127.0.0.1:9100' "HANDOFF cita a porta 9100 no loopback"
tem $H 'Loki' "HANDOFF registra o Loki na borda"
# Nuvem laranja: Traefik confia no X-Forwarded-For só vindo da Cloudflare.
tem traefik/traefik.yml 'trustedIPs' "traefik.yml: forwardedHeaders.trustedIPs nas entradas públicas"
tem traefik/traefik.yml '173.245.48.0/20' "traefik.yml: faixas IPv4 da Cloudflare"
tem traefik/traefik.yml '2400:cb00::/32' "traefik.yml: faixas IPv6 da Cloudflare"
tem README.md '## Nuvem laranja da Cloudflare' "README: seção da nuvem laranja"
tem README.md 'https://www.cloudflare.com/ips-v4' "README: de onde vêm as faixas da Cloudflare"
tem README.md 'Full (strict)' "README: modo SSL/TLS Full (strict)"
tem README.md 'loki_dados_bytes' "README: disco do Loki publicado pelo node exporter"
tem docker-compose.yml '--collector.textfile.directory=/textfile' "node exporter lê o textfile do disco do Loki"
# Dependabot: um PR mensal com as imagens da borda e outro com as actions.
D=.github/dependabot.yml
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Cada entrada de update vai para um arquivo, para conferir uma de cada vez.
bloco() { # ecossistema -> arquivo com só aquela entrada
  awk -v e="$1" '/^  - package-ecosystem: /{on=($0 == "  - package-ecosystem: " e)} on' $D > "$tmp/$1"
  echo "$tmp/$1"
}
DC=$(bloco docker-compose)
DA=$(bloco github-actions)
tem_re $D '^  - package-ecosystem: docker-compose$' "Dependabot: ecossistema docker-compose"
tem_re $DC '^    directories:$' "Dependabot: docker-compose numa entrada só, com lista de diretórios (um PR por mês)"
tem_re $DC '^      - "/"$' "Dependabot: diretório / (compose principal)"
tem_re $DC '^      - "/exemplos/whoami"$' "Dependabot: diretório /exemplos/whoami"
nao_tem $DC '    directory:' "Dependabot: docker-compose sem entrada separada por diretório"
n=$(grep -cE '^  - package-ecosystem: docker-compose$' $D)
if [ "$n" = 1 ]; then echo "ok    Dependabot: uma única entrada de docker-compose"; else echo "FALHA Dependabot: esperada 1 entrada de docker-compose, há $n"; falhas=$((falhas + 1)); fi
n=$(grep -cE '^  - package-ecosystem:' $D)
if [ "$n" = 2 ]; then echo "ok    Dependabot: duas entradas (imagens e actions)"; else echo "FALHA Dependabot: esperadas 2 entradas de update, há $n"; falhas=$((falhas + 1)); fi
tem $DC 'interval: monthly' "Dependabot: imagens com agenda mensal"
tem $DC 'default-days: 14' "Dependabot: imagens com cooldown de 14 dias"
tem $DC 'dependency-name: busybox' "Dependabot: regra do BusyBox"
tem $DC 'version-update:semver-minor' "Dependabot: BusyBox sem salto de linha (semver-minor ignorado)"
nao_tem $D 'open-pull-requests-limit: 0' "Dependabot: limite de PRs acima de 0"
tem_re $D '^  - package-ecosystem: github-actions$' "Dependabot: ecossistema github-actions"
tem $DA 'directory: "/"' "Dependabot: actions lidas de / (.github/workflows)"
tem $DA 'interval: monthly' "Dependabot: actions com agenda mensal"
tem $DA 'default-days: 14' "Dependabot: actions com cooldown de 14 dias"
tem_re $DA '^    groups:$' "Dependabot: actions num grupo só (um PR por mês)"
tem_re $DA '^          - "\*"$' "Dependabot: grupo das actions pega todas"
# Nenhum workflow de auto-merge: nada que mescle ou aprove PR sozinho.
for f in .github/workflows/*; do
  [ -e "$f" ] || continue
  for p in 'gh pr merge' 'gh pr review' '--auto' 'pull_request_target' 'dependabot/fetch-metadata' 'auto-merge' 'automerge'; do
    nao_tem "$f" "$p" "sem auto-merge: $f não tem '$p'"
  done
done
# Workflow de deploy da borda: só pelo botão, só da main, no Environment
# producao, ssh do runner com o host conferido e curl nos dois domínios.
W=.github/workflows/deploy-borda.yml
if [ -f $W ]; then echo "ok    workflow de deploy da borda existe ($W)"; else echo "FALHA workflow de deploy da borda não existe ($W)"; falhas=$((falhas + 1)); fi
n=$(ls .github/workflows 2>/dev/null | wc -l)
if [ "$n" = 1 ]; then echo "ok    só o workflow de deploy em .github/workflows"; else echo "FALHA .github/workflows deveria ter só o deploy-borda.yml, há $n arquivo(s)"; falhas=$((falhas + 1)); fi
tem_re $W '^  workflow_dispatch:' "workflow: disparo manual (workflow_dispatch)"
n=$(awk '/^on:/{on=1; next} /^[^ #]/{on=0} on && /^  [a-z_]+:/' $W 2>/dev/null | wc -l)
if [ "$n" = 1 ]; then echo "ok    workflow: único gatilho é o manual"; else echo "FALHA workflow: esperado só o gatilho workflow_dispatch, há $n"; falhas=$((falhas + 1)); fi
nao_tem $W 'push:' "workflow: sem gatilho de push"
nao_tem $W 'pull_request' "workflow: sem gatilho de PR"
nao_tem $W 'schedule:' "workflow: sem gatilho agendado"
tem $W "github.ref != 'refs/heads/main'" "workflow: recusa rodar fora da main"
tem_re $W '^    environment: producao$' "workflow: usa o Environment producao"
tem_re $W '^permissions: \{\}$' "workflow: sem permissões do GITHUB_TOKEN"
for s in VPS_HOST VPS_SSH_KEY VPS_KNOWN_HOSTS; do
  tem $W "secrets.$s" "workflow: usa o secret $s"
done
tem $W 'deploy@' "workflow: entra como o usuário deploy"
tem $W 'StrictHostKeyChecking=yes' "workflow: confere a impressão digital da VPS"
tem $W 'UserKnownHostsFile=' "workflow: known_hosts do secret, em arquivo"
tem $W 'IdentitiesOnly=yes' "workflow: usa só a chave do secret"
tem $W 'mktemp' "workflow: chave e known_hosts em arquivos temporários"
nao_tem $W 'actions/checkout' "workflow: sem checkout"
if grep -qiE '^\s*-?\s*uses:.*ssh' $W 2>/dev/null; then echo "FALHA workflow: action de terceiros para SSH"; falhas=$((falhas + 1)); else echo "ok    workflow: sem action de terceiros para SSH"; fi
tem $W 'https://conantorres.dev/' "workflow: curl no conantorres.dev"
tem $W 'https://bbcontainermodular.com/' "workflow: curl no bbcontainer"
tem $W '"200"' "workflow: curl exige 200"
tem README.md 'Insights → Dependency graph → Dependabot' "README: onde conferir a leitura do Dependabot"
tem README.md 'Atualização das imagens (Dependabot)' "README: item do Dependabot no checklist manual"
tem_re README.md 'Dependency graph → Dependabot que o GitHub leu' "README: checklist manual manda conferir o Dependency graph depois do merge"
tem README.md 'PR do Dependabot' "README: roteiro de revisão do PR do Dependabot"
tem README.md 'IMAGEM_LOKI' "README: aprovar PR do Loki atualiza o Loki falso do homelab (smoke.env)"
tem README.md 'Loki da borda:' "README: aprovar PR do Loki atualiza a nota de versão do homelab"
# Deploy pelo CI: usuário deploy, sudoers, chaves e Environment (ticket 04).
tem README.md '## Deploy pelo CI (usuário `deploy`)' "README: seção do usuário deploy"
tem README.md 'install -m 755 -o root -g root /opt/traefik/vps/deploy-vps.sh /usr/local/sbin/deploy-vps' "README: instala o deploy-vps como root"
tem README.md '--shell /bin/sh deploy' "README: deploy com shell real (/bin/sh)"
nao_tem README.md 'usermod -aG docker deploy' "README: deploy fora do grupo docker"
tem README.md 'Defaults!/usr/local/sbin/deploy-vps env_keep += "SSH_ORIGINAL_COMMAND"' "README: sudoers mantém só SSH_ORIGINAL_COMMAND"
tem README.md 'deploy ALL=(root) NOPASSWD: /usr/local/sbin/deploy-vps conan-torres, /usr/local/sbin/deploy-vps traefik' "README: sudoers libera só o script com os dois argumentos"
tem README.md 'visudo -cf' "README: valida o sudoers com visudo -cf"
tem README.md 'restrict,command="sudo /usr/local/sbin/deploy-vps conan-torres"' "README: chave do conan-torres presa ao projeto"
tem README.md 'restrict,command="sudo /usr/local/sbin/deploy-vps traefik"' "README: chave do traefik-default presa à borda"
tem README.md 'ssh-keygen -t ed25519' "README: uma chave ed25519 por repositório"
tem README.md 'ssh-keyscan' "README: known_hosts pelo ssh-keyscan"
tem README.md 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub' "README: impressão digital conferida na VPS"
tem README.md 'Environment `producao`' "README: Environment producao"
tem README.md 'Selected branches and tags' "README: Environment limitado por regra de branch"
for s in VPS_HOST VPS_SSH_KEY VPS_KNOWN_HOSTS; do
  tem README.md "$s" "README: secret $s"
done
tem README.md '--env producao' "README: secrets do Environment, não do repositório"
tem README.md 'docker login ghcr.io` do root' "README: deploy-vps usa o docker login do root"
tem README.md '.github/workflows/deploy-borda.yml' "README: aponta o workflow de deploy da borda"
tem README.md 'Run workflow' "README: deploy da borda pelo botão Run workflow"
tem README.md 'github-actions' "README: Dependabot também vigia as actions"
# Guia (ticket 07): CI por SSH para os sites com marcador; cron para os demais.
tem $G '.deploy-pelo-ci' "guia: CI por SSH para sites com .deploy-pelo-ci"
tem $G 'Pelo cron (os demais sites)' "guia: cron como caminho dos demais sites"
tem $G 'Deploy pelo CI (usuário `deploy`)' "guia aponta a seção do README"
nao_tem $G 'GitHub Actions por SSH (evolução)' "guia: CI por SSH deixa de ser evolução"
# Checklist do primeiro deploy na ordem segura da SPEC (instalar → secrets → marcador → job).
tem README.md '### Checklist do primeiro deploy' "README: checklist do primeiro deploy"
ordem() { # arquivo antes depois descrição
  local a b
  a=$(grep -nF -- "$2" "$1" | head -1 | cut -d: -f1)
  b=$(grep -nF -- "$3" "$1" | head -1 | cut -d: -f1)
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then
    echo "ok    $4"
  else
    echo "FALHA $4 ($2 deveria vir antes de $3)"
    falhas=$((falhas + 1))
  fi
}
ordem README.md '**1. Instalar na VPS**' '**2. Environments e secrets**' "checklist: instalar na VPS antes dos secrets"
ordem README.md '**2. Environments e secrets**' '**3. Marcador da pasta do site**' "checklist: secrets antes do marcador"
ordem README.md '**3. Marcador da pasta do site**' '**4. Mesclar o job do conan-torres**' "checklist: marcador antes do job"
ordem README.md '**4. Mesclar o job do conan-torres**' '**5. Primeiro deploy**' "checklist: job antes do primeiro deploy"
ordem README.md '**5. Primeiro deploy**' '**6. Falha forçada e e-mail**' "checklist: falha forçada por último"
tem README.md 'sudo touch /opt/apps/conan-torres/.deploy-pelo-ci' "checklist: marcador da pasta do conan-torres"
tem README.md 'linhas novas de `conan-torres`' "checklist: cron deixa o conan-torres de fora"
tem README.md 'ERRO: SHA inválido' "checklist: chave de outro repositório recusada"
tem README.md 'Only notify for failed workflows' "checklist: e-mail só para execução que falha"
tem README.md 'IMAGE_TAG=<sha>' "checklist: falha forçada com IMAGE_TAG"
exit $((falhas > 0))
