#!/usr/bin/env bash
# Smoke test local da pilha de borda.
#
# Sobe o Traefik + docker-socket-proxy (docker-compose.yml da raiz) e os sites
# de teste (o exemplo do guia em exemplos/whoami + extras em
# testes/sites-extras.yml), verifica o comportamento "por fora" com curl e
# derruba tudo no final, mesmo se algo falhar.
#
# ATENÇÃO: usa as portas 80 e 443 do host. Não rode com outra pilha do
# Traefik (ou qualquer coisa nessas portas) de pé.
#
# Uso:   testes/smoke.sh
# Saída: código 0 se todas as verificações passarem; diferente de zero se
#        alguma falhar ou se a pilha não subir.
#
# Como estender: crie um arquivo testes/verificacoes/NN-nome.sh. Todos os
# arquivos dessa pasta são carregados em ordem alfabética depois que a pilha
# está de pé, e podem usar as funções de testes/lib.sh (req, afirmar_status,
# afirmar_cabecalho, ...), as funções borda/sites/vizinho abaixo e as
# variáveis ID_TRAEFIK e IMAGEM_TRAEFIK (definidas depois que a pilha sobe).

set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ" || exit 1

# shellcheck source=testes/lib.sh
. "$RAIZ/testes/lib.sh"

# Variáveis do teste (também lidas pelos composes via testes/smoke.env).
set -a
# shellcheck source=testes/smoke.env
. "$RAIZ/testes/smoke.env"
set +a
export IP_TESTE="${IP_TESTE:-127.0.0.1}"
export HOST_TESTE="$DOMINIO"

# Dois projetos separados, como na VPS: a borda em /opt/traefik e cada site
# no seu próprio compose. --env-file evita ler o .env real da máquina.
borda() {
  docker compose -p traefik-smoke-borda --env-file "$RAIZ/testes/smoke.env" \
    -f "$RAIZ/docker-compose.yml" "$@"
}
sites() {
  docker compose -p traefik-smoke-sites --env-file "$RAIZ/testes/smoke.env" \
    -f "$RAIZ/exemplos/whoami/docker-compose.yml" \
    -f "$RAIZ/testes/sites-extras.yml" "$@"
}

# vizinho ARGS...  -> roda o wget (BusyBox) num container descartável na rede
# "proxy", como se fosse um site vizinho. Usa a mesma imagem do Traefik
# (que tem wget), lida do container em execução: a tag fica só no
# docker-compose.yml.
vizinho() {
  docker run --rm --network proxy --entrypoint wget "$IMAGEM_TRAEFIK" "$@"
}

# Imagem do whoami: a tag fica só no exemplo; o sites-extras.yml usa esta.
IMAGEM_WHOAMI="$(docker compose --env-file "$RAIZ/testes/smoke.env" \
  -f "$RAIZ/exemplos/whoami/docker-compose.yml" config --images)" || exit 1
export IMAGEM_WHOAMI

REDE_CRIADA=0

limpar() {
  secao "Derrubando a pilha"
  sites down -v --remove-orphans >/dev/null 2>&1 || true
  borda down -v --remove-orphans >/dev/null 2>&1 || true
  if [ "$REDE_CRIADA" = 1 ]; then
    docker network rm proxy >/dev/null 2>&1 || true
  fi
}

finalizar() {
  local rc=$?
  limpar
  if [ "$rc" -eq 0 ] && [ "$FALHAS" -gt 0 ]; then
    rc=1
  fi
  printf '\nResultado: %d ok, %d falha(s). Código de saída: %d\n' \
    "$SUCESSOS" "$FALHAS" "$rc"
  exit "$rc"
}
trap finalizar EXIT
trap 'exit 130' INT TERM

secao "Subindo a pilha"

# A rede "proxy" é externa (criada uma vez por servidor). Só criamos aqui se
# ela não existir, e só removemos no final se fomos nós que criamos.
if ! docker network inspect proxy >/dev/null 2>&1; then
  docker network create proxy >/dev/null || exit 1
  REDE_CRIADA=1
fi

if ! borda up -d --wait --wait-timeout 90; then
  echo "A borda (Traefik + socket-proxy) não ficou saudável." >&2
  borda logs --tail 50 >&2 || true
  exit 1
fi

# Lidos uma vez aqui e usados por todas as verificações.
ID_TRAEFIK="$(borda ps -q traefik)"
IMAGEM_TRAEFIK="$(docker inspect -f '{{.Config.Image}}' "$ID_TRAEFIK")"

if ! sites up -d --wait --wait-timeout 60; then
  echo "Os sites de teste não subiram." >&2
  sites logs --tail 50 >&2 || true
  exit 1
fi

# A descoberta de containers pelo Traefik é assíncrona: espera o whoami
# começar a responder antes das verificações.
whoami_responde() {
  req https "$HOST_TESTE" /
  [ "$RESP_STATUS" = 200 ]
}
if ! esperar_ate 30 whoami_responde; then
  echo "O whoami não ficou acessível via Traefik em 30s." >&2
  borda logs --tail 50 traefik >&2 || true
fi

for arquivo in "$RAIZ"/testes/verificacoes/*.sh; do
  # shellcheck source=/dev/null
  . "$arquivo"
done
