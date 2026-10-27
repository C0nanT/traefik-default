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
tem README.md 'restrict,port-forwarding,permitopen="127.0.0.1:8082",permitopen="127.0.0.1:9100"' "README: chave restrita às portas 8082 e 9100"
tem README.md 'AllowTcpForwarding' "README: conferir AllowTcpForwarding do sshd"
tem README.md 'sshd -T' "README: conferir a config efetiva do sshd"
tem README.md 'administratively prohibited' "README: teste manual da porta recusada"
tem README.md '../homelab-monitoring' "README linka o homelab-monitoring"
H=.scratch/traefik-vps-base/HANDOFF.md
nao_tem README.md 'Basta subir um Prometheus na rede' "próximos passos sem o plano antigo do Prometheus na rede proxy"
tem README.md '../homelab-monitoring#colocar-no-ar' "próximos passos aponta para colocar no ar do homelab-monitoring"
tem $H 'node exporter' "HANDOFF registra o node exporter"
tem $H 'metricas' "HANDOFF registra o usuário metricas"
tem $H 'no ar, falta o Telegram' "HANDOFF: item 2 no ar, pendente só o Telegram"
tem $H '127.0.0.1:9100' "HANDOFF cita a porta 9100 no loopback"
# Nuvem laranja: Traefik confia no X-Forwarded-For só vindo da Cloudflare.
tem traefik/traefik.yml 'trustedIPs' "traefik.yml: forwardedHeaders.trustedIPs nas entradas públicas"
tem traefik/traefik.yml '173.245.48.0/20' "traefik.yml: faixas IPv4 da Cloudflare"
tem traefik/traefik.yml '2400:cb00::/32' "traefik.yml: faixas IPv6 da Cloudflare"
tem README.md '## Nuvem laranja da Cloudflare' "README: seção da nuvem laranja"
tem README.md 'https://www.cloudflare.com/ips-v4' "README: de onde vêm as faixas da Cloudflare"
tem README.md 'Full (strict)' "README: modo SSL/TLS Full (strict)"
exit $((falhas > 0))
