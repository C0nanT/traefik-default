#!/usr/bin/env bash
# Atualiza os sites em /opt/apps: puxa imagens novas do GHCR e recria só o que mudou.
# Rodado pelo cron (/etc/cron.d/atualizar-apps). O próprio script anexa a saída em
# /var/log/atualizar-apps/atualizar-apps.log (pasta só do cron, que o Alloy monta;
# cria a pasta se faltar).
# APPS_RAIZ, TRAVA_ARQUIVO, LOG_ARQUIVO e METRICAS_DIR só mudam os caminhos (usados nos testes); o padrão é produção.
# No fim de cada rodada grava deploy.prom no volume "textfile" da borda (o node
# exporter publica): deploy_falhou{app} (0/1 por site) e o horário da rodada.
# Se a métrica falhar, vira uma linha no log e o deploy segue igual.
# Opcional por site: com um arquivo .origem na pasta (REPO=, ARQUIVO=, RAMO=,
# CHAVE=), o docker-compose.yml é trocado pelo da origem quando ela muda, depois
# de passar no `docker compose config`. Se a sincronia falhar, o arquivo atual
# fica, vira ERRO no log (deploy_falhou 1) e pull + up -d seguem igual.
set -uo pipefail
export GIT_TERMINAL_PROMPT=0
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

# sincroniza_compose: roda na pasta do site. Sem .origem, não faz nada. Com ela,
# busca o último commit do RAMO (cache git em .origem.git) e, se ARQUIVO mudou,
# valida e troca o docker-compose.yml. Saída: "compose atualizado <site> (<commit>)"
# quando troca; a mensagem do erro (código 1) quando falha.
sincroniza_compose() {
  local repo="" arquivo=docker-compose.yml ramo=main chave="" nome valor commit
  local novo=.docker-compose.yml.novo
  local ssh=()
  [ -f .origem ] || return 0
  while IFS='=' read -r nome valor; do
    case "$nome" in
      REPO) repo=$valor ;;
      ARQUIVO) arquivo=$valor ;;
      RAMO) ramo=$valor ;;
      CHAVE) chave=$valor ;;
    esac
  done <.origem
  [ -n "$repo" ] || { echo ".origem sem REPO"; return 1; }
  [ -n "$chave" ] && ssh=(GIT_SSH_COMMAND="ssh -i $chave -o IdentitiesOnly=yes -o BatchMode=yes")
  [ -d .origem.git ] || git init -q --bare .origem.git || return 1
  env "${ssh[@]}" timeout 60 git --git-dir=.origem.git fetch -q --depth 1 "$repo" "+refs/heads/$ramo:refs/origem" || return 1
  commit=$(git --git-dir=.origem.git rev-parse --short refs/origem) || return 1
  git --git-dir=.origem.git show "refs/origem:$arquivo" >"$novo" || { rm -f "$novo"; return 1; }
  if cmp -s "$novo" docker-compose.yml; then
    rm -f "$novo"
    return 0
  fi
  docker compose -f "$novo" config -q && mv "$novo" docker-compose.yml || { rm -f "$novo"; return 1; }
  echo "compose atualizado $app ($commit)"
}

for dir in "${APPS_RAIZ:-/opt/apps}"/*/; do
  [ -f "$dir/docker-compose.yml" ] || continue
  cd "$dir" || continue
  app=$(basename "$dir")
  falhou[$app]=0
  if saida=$(sincroniza_compose 2>&1); then
    [ -n "$saida" ] && echo "$(date -Is) $saida"
  else
    echo "$(date -Is) ERRO $app: compose: ${saida//$'\n'/ }"
    falhou[$app]=1
  fi
  if ! saida=$(docker compose pull -q 2>&1 && docker compose up -d --remove-orphans 2>&1); then
    # Uma linha só: o erro do docker tem várias, e as seguintes ficariam sem data nem ERRO.
    echo "$(date -Is) ERRO $app: ${saida//$'\n'/ }"
    falhou[$app]=1
  else
    if grep -qE 'Recreate|Started|Created' <<<"$saida"; then
      echo "$(date -Is) atualizado $app"
    fi
  fi
done

docker image prune -f >/dev/null 2>&1

if ! erro=$(grava_metricas 2>&1); then
  echo "$(date -Is) ERRO métrica: $erro"
fi
