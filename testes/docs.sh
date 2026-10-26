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
exit $((falhas > 0))
