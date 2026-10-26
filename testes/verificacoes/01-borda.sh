# shellcheck shell=bash
# Verificações da pilha mínima de borda (ticket 01).
# Carregado pelo testes/smoke.sh; usa as funções de testes/lib.sh.

secao "Borda: containers"

ID_SOCKET="$(borda ps -q socket-proxy)"

saude() {
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$1" 2>/dev/null
}

afirmar "Traefik está saudável (healthcheck via ping)" \
  test "$(saude "$ID_TRAEFIK")" = healthy
afirmar "socket-proxy está saudável" \
  test "$(saude "$ID_SOCKET")" = healthy

montagens_traefik="$(docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' "$ID_TRAEFIK")"
afirmar "o socket do Docker não está montado no Traefik" \
  test "${montagens_traefik/docker.sock/}" = "$montagens_traefik"

# Lista com espaço antes de cada nome, para casar só a rede "proxy" exata.
redes_socket="$(docker inspect -f '{{range $n, $_ := .NetworkSettings.Networks}} {{$n}} {{end}}' "$ID_SOCKET")"
afirmar "o socket-proxy não está na rede proxy" \
  test "${redes_socket/ proxy /}" = "$redes_socket"

secao "Borda: socket-proxy só libera leitura"

# Testado de dentro do Traefik, o único cliente legítimo do socket-proxy.
# O wget (BusyBox) da imagem do Traefik sai com erro em respostas 4xx/5xx.
no_traefik() {
  docker exec "$ID_TRAEFIK" "$@"
}
URL_SOCKET="http://socket-proxy:2375"

afirmar "leitura de containers é permitida (GET /containers/json)" \
  no_traefik wget -q -O /dev/null "$URL_SOCKET/containers/json"
afirmar "versão da API é permitida (GET /version)" \
  no_traefik wget -q -O /dev/null "$URL_SOCKET/version"

if no_traefik wget -q -O /dev/null "$URL_SOCKET/images/json" >/dev/null 2>&1; then
  falha "endpoint não usado pelo Traefik é bloqueado (GET /images/json)"
else
  ok "endpoint não usado pelo Traefik é bloqueado (GET /images/json)"
fi

if no_traefik wget -q -O /dev/null --post-data='{}' \
  "$URL_SOCKET/containers/create" >/dev/null 2>&1; then
  falha "escrita é bloqueada (POST /containers/create)"
else
  ok "escrita é bloqueada (POST /containers/create)"
fi

secao "Borda: HTTP -> HTTPS"

req http "$HOST_TESTE" "/algum/caminho?x=1"
afirmar_status "HTTP responde com redirecionamento permanente" 301 308
afirmar_cabecalho "o redirecionamento leva para HTTPS preservando caminho e query" \
  Location "https://$HOST_TESTE/algum/caminho?x=1"

secao "Borda: roteamento"

req https "$HOST_TESTE" /
afirmar_status "o whoami responde via HTTPS" 200
afirmar_corpo_contem "a resposta vem do whoami (eco do Host)" "Host: $HOST_TESTE"

# O container sem label tem uma regra Host() completa, mas não tem
# traefik.enable=true: o 404 prova que exposedByDefault=false está valendo.
req https "$HOST_SEM_LABEL" /
afirmar_status "container sem traefik.enable=true não é roteado" 404
afirmar_corpo_nao_contem "a resposta não vem do container sem label" "Hostname:"

secao "Borda: painel e API fora das portas públicas"

# Nunca usar o host do whoami aqui: ele responde 200 em qualquer caminho.
for host in "" "nao-roteado.smoke.test"; do
  rotulo="${host:-IP direto}"
  for caminho in /api/rawdata /api/overview /dashboard/; do
    req https "$host" "$caminho"
    afirmar_status "HTTPS $rotulo$caminho não expõe o painel/API" 404
    afirmar_corpo_nao_contem "HTTPS $rotulo$caminho sem JSON da API" '"routers"'

    req http "$host" "$caminho" -L
    afirmar_status "HTTP $rotulo$caminho (seguindo redirecionamento) não expõe o painel/API" 404
    afirmar_corpo_nao_contem "HTTP $rotulo$caminho sem JSON da API" '"routers"'
  done
done
