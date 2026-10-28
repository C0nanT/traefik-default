#!/usr/bin/env bash
# Deploy pelo CI: chamado pelo comando forçado do usuário `deploy` no
# authorized_keys (`command="sudo /usr/local/sbin/deploy-vps <projeto>"`).
# Roda como root. O projeto vem só do argumento (fixado no authorized_keys,
# nunca do GitHub); nada do que o GitHub manda vira comando.
# Uso: deploy-vps <projeto>   (projetos: conan-torres; traefik no ticket 03)
#   conan-torres: SHA do commit em SSH_ORIGINAL_COMMAND; pull + up -d, espera
#   `healthy` e confere que a imagem em uso é a do SHA. Sem rollback.
# Sai com 0 se o deploy deu certo; 1 com "ERRO: ..." em qualquer recusa ou falha.
#
# sudoers (o env_reset padrão apaga o ambiente; só o SHA pode passar):
#   Defaults!/usr/local/sbin/deploy-vps env_keep += "SSH_ORIGINAL_COMMAND"
#   deploy ALL=(root) NOPASSWD: /usr/local/sbin/deploy-vps conan-torres, /usr/local/sbin/deploy-vps traefik
# APPS_RAIZ, TRAVA_ARQUIVO, TRAVA_ESPERA e PRAZO_SAUDAVEL só existem para o
# teste local (testes/deploy.sh); pelo sudo nunca chegam, e o padrão é produção.
set -uo pipefail

erro() { echo "ERRO: $*" >&2; exit 1; }

# SHA do commit: único dado vindo do GitHub, entregue pelo SSH em
# SSH_ORIGINAL_COMMAND. Só 40 caracteres hexadecimais minúsculos, conferido
# antes de qualquer uso; se for inválido, nunca é ecoado nem usado.
valida_sha() {
  sha="${SSH_ORIGINAL_COMMAND-}"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] \
    || erro "SHA inválido: esperado o commit completo (40 caracteres hexadecimais)"
}

# numero NOME VALOR: aceita só inteiro (vai para aritmética e para o flock).
numero() { [[ "$2" =~ ^[0-9]+$ ]] || erro "$1 inválido: '$2'"; }

# Mesma trava do cron (vps/atualizar-apps.sh), para não rodar junto com ele
# nem com outro deploy. Diferente do cron, espera a vez por tempo limitado.
pega_trava() {
  local espera="${TRAVA_ESPERA:-300}"
  numero TRAVA_ESPERA "$espera"
  exec 9>"${TRAVA_ARQUIVO:-/run/atualizar-apps.lock}" || erro "não consegui abrir a trava"
  flock -w "$espera" 9 \
    || erro "trava ocupada (cron ou outro deploy) por mais de ${espera}s; tente de novo"
}

IMAGEM="ghcr.io/c0nant/conan-torres"
SERVICO=web

# Deploy de um site em /opt/apps (compose usa a tag `latest`).
deploy_site() {
  local pasta="${APPS_RAIZ:-/opt/apps}/$projeto"
  cd "$pasta" || erro "pasta $pasta não encontrada"

  # IMAGE_TAG no .env = versão travada de propósito pelo dono: o CI não
  # desfaz. O .env só é lido com grep, nunca carregado (rodamos como root).
  # IMAGE_TAG vazio cai em `latest` no compose, então não trava.
  if [ -f .env ] && grep -qE \
    '^[[:space:]]*(export[[:space:]]+)?IMAGE_TAG[[:space:]]*=[[:space:]]*[^[:space:]#]' .env; then
    erro "versão travada: IMAGE_TAG definido em $pasta/.env; tire-o para voltar ao deploy pelo CI"
  fi

  docker compose pull -q || erro "docker compose pull falhou"
  docker compose up -d --remove-orphans || erro "docker compose up -d falhou"

  local container
  container="$(docker compose ps -q "$SERVICO")" || erro "docker compose ps falhou"
  [ -n "$container" ] || erro "nenhum container do serviço $SERVICO depois do up -d"
  [[ "$container" != *$'\n'* ]] || erro "mais de um container do serviço $SERVICO"

  # Espera o healthcheck da imagem dar `healthy`, até o prazo.
  local prazo="${PRAZO_SAUDAVEL:-120}" saude=""
  numero PRAZO_SAUDAVEL "$prazo"
  local fim=$((SECONDS + prazo))
  while :; do
    saude="$(docker inspect --format \
      '{{if .State.Health}}{{.State.Health.Status}}{{else}}sem-healthcheck{{end}}' \
      "$container")" || erro "docker inspect do container falhou"
    [ "$saude" = healthy ] && break
    [ "$SECONDS" -ge "$fim" ] \
      && erro "container de $projeto não ficou healthy em ${prazo}s (estado: $saude)"
    sleep 2
  done

  # A imagem em uso tem de ser a do commit que o CI construiu.
  # Compara o ID da imagem (digest da config) do container com o da tag do
  # SHA: iguais = mesma imagem, sem depender do formato do RepoDigests.
  docker pull -q "$IMAGEM:$sha" >/dev/null || erro "não consegui baixar $IMAGEM:$sha"
  local em_uso do_sha
  em_uso="$(docker inspect --format '{{.Image}}' "$container")" \
    || erro "docker inspect do container falhou"
  do_sha="$(docker image inspect --format '{{.Id}}' "$IMAGEM:$sha")" \
    || erro "docker image inspect de $IMAGEM:$sha falhou"
  [ -n "$em_uso" ] && [ "$em_uso" = "$do_sha" ] \
    || erro "a imagem em uso ($em_uso) não é a do commit $sha ($do_sha)"
  # Tira só a tag do SHA (a imagem segue como `latest`), para as tags de
  # cada deploy não se acumularem no disco.
  docker image rm "$IMAGEM:$sha" >/dev/null 2>&1 || true
  echo "deploy de $projeto ok: $IMAGEM:$sha"
}

[ "$#" -eq 1 ] || erro "uso: deploy-vps <projeto>"
projeto="$1"

case "$projeto" in
  conan-torres)
    valida_sha
    pega_trava
    deploy_site
    ;;
  traefik)
    # Deploy da borda (/opt/traefik): entra no ticket 03.
    erro "deploy da borda (traefik) ainda não implementado"
    ;;
  *) erro "projeto '$projeto' não permitido" ;;
esac
