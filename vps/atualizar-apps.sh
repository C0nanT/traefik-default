#!/usr/bin/env bash
# Atualiza os sites em /opt/apps: puxa imagens novas do GHCR e recria só o que mudou.
# Rodado pelo cron (/etc/cron.d/atualizar-apps). Log em /var/log/atualizar-apps.log.
# Pasta com o arquivo-marcador .deploy-pelo-ci é atualizada pelo CI: o cron pula.
# APPS_RAIZ e TRAVA_ARQUIVO só mudam os caminhos (usados nos testes); o padrão é produção.
set -uo pipefail
exec 9>"${TRAVA_ARQUIVO:-/run/atualizar-apps.lock}"
flock -n 9 || exit 0

for dir in "${APPS_RAIZ:-/opt/apps}"/*/; do
  [ -f "$dir/docker-compose.yml" ] || continue
  [ -e "$dir/.deploy-pelo-ci" ] && continue
  cd "$dir" || continue
  if ! saida=$(docker compose pull -q 2>&1 && docker compose up -d --remove-orphans 2>&1); then
    echo "$(date -Is) ERRO $(basename "$dir"): $saida"
  elif grep -qE 'Recreate|Started|Created' <<<"$saida"; then
    echo "$(date -Is) atualizado $(basename "$dir")"
  fi
done

docker image prune -f >/dev/null 2>&1
