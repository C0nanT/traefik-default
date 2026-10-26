#!/usr/bin/env bash
# Atualiza os sites em /opt/apps: puxa imagens novas do GHCR e recria só o que mudou.
# Rodado pelo cron (/etc/cron.d/atualizar-apps). Log em /var/log/atualizar-apps.log.
set -uo pipefail
exec 9>/run/atualizar-apps.lock
flock -n 9 || exit 0

for dir in /opt/apps/*/; do
  [ -f "$dir/docker-compose.yml" ] || continue
  cd "$dir" || continue
  if ! saida=$(docker compose pull -q 2>&1 && docker compose up -d --remove-orphans 2>&1); then
    echo "$(date -Is) ERRO $(basename "$dir"): $saida"
  elif grep -qE 'Recreate|Started|Created' <<<"$saida"; then
    echo "$(date -Is) atualizado $(basename "$dir")"
  fi
done

docker image prune -f >/dev/null 2>&1
