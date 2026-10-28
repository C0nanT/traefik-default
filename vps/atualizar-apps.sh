#!/usr/bin/env bash
# Atualiza os sites em /opt/apps: puxa imagens novas do GHCR e recria só o que mudou.
# Rodado pelo cron (/etc/cron.d/atualizar-apps). O próprio script anexa a saída em
# /var/log/atualizar-apps/atualizar-apps.log (pasta só do cron, que o Alloy monta;
# cria a pasta se faltar).
# APPS_RAIZ, TRAVA_ARQUIVO, LOG_ARQUIVO e METRICAS_DIR só mudam os caminhos (usados nos testes); o padrão é produção.
# No fim de cada rodada grava deploy.prom no volume "textfile" da borda (o node
# exporter publica): deploy_falhou{app} (0/1 por site) e o horário da rodada.
# Se a métrica falhar, vira uma linha no log e o deploy segue igual.
set -uo pipefail
exec 9>"${TRAVA_ARQUIVO:-/run/atualizar-apps.lock}"
flock -n 9 || exit 0

LOG_ARQUIVO="${LOG_ARQUIVO:-/var/log/atualizar-apps/atualizar-apps.log}"
mkdir -p "$(dirname "$LOG_ARQUIVO")"
exec >>"$LOG_ARQUIVO" 2>&1

declare -A falhou=()

# Diretório da métrica: METRICAS_DIR ou o mountpoint do volume real da borda.
diretorio_metricas() {
  [ -n "${METRICAS_DIR:-}" ] && { echo "$METRICAS_DIR"; return; }
  docker volume inspect -f '{{.Mountpoint}}' "${METRICAS_VOLUME:-traefik_textfile}"
}

# Grava deploy.prom de uma vez: temporário no mesmo diretório e rename.
grava_metricas() {
  local destino tmp app rotulo
  destino=$(diretorio_metricas) && [ -n "$destino" ] || { echo "sem diretório"; return 1; }
  tmp=$(mktemp "$destino/.deploy.prom.XXXXXX") || return 1
  {
    echo "# HELP deploy_falhou 1 se o deploy do site falhou na última rodada do cron."
    echo "# TYPE deploy_falhou gauge"
    for app in "${!falhou[@]}"; do
      rotulo=${app//\\/\\\\}   # escapa \ e " do valor do rótulo
      rotulo=${rotulo//\"/\\\"}
      echo "deploy_falhou{app=\"$rotulo\"} ${falhou[$app]}"
    done
    echo "# HELP deploy_rodada_timestamp_seconds Horário Unix do fim da última rodada do cron."
    echo "# TYPE deploy_rodada_timestamp_seconds gauge"
    echo "deploy_rodada_timestamp_seconds $(date +%s)"
  } >"$tmp" && chmod 644 "$tmp" && mv "$tmp" "$destino/deploy.prom" || { rm -f "$tmp"; return 1; }
}

for dir in "${APPS_RAIZ:-/opt/apps}"/*/; do
  [ -f "$dir/docker-compose.yml" ] || continue
  cd "$dir" || continue
  app=$(basename "$dir")
  if ! saida=$(docker compose pull -q 2>&1 && docker compose up -d --remove-orphans 2>&1); then
    # Uma linha só: o erro do docker tem várias, e as seguintes ficariam sem data nem ERRO.
    echo "$(date -Is) ERRO $app: ${saida//$'\n'/ }"
    falhou[$app]=1
  else
    falhou[$app]=0
    if grep -qE 'Recreate|Started|Created' <<<"$saida"; then
      echo "$(date -Is) atualizado $app"
    fi
  fi
done

docker image prune -f >/dev/null 2>&1

if ! erro=$(grava_metricas 2>&1); then
  echo "$(date -Is) ERRO métrica: $erro"
fi
