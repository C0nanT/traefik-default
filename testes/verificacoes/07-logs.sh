# shellcheck shell=bash
# Verificações dos logs no Loki (Alloy coleta, Loki guarda), só no loopback.
# Carregado pelo testes/smoke.sh; usa as funções de testes/lib.sh.
#
# Tudo visto de fora, como o Grafana veria: consultas LogQL na API do Loki
# em 127.0.0.1:3100 (o caminho do túnel SSH).

secao "Logs: containers"

ID_LOKI="$(borda ps -q loki)"
ID_ALLOY="$(borda ps -q alloy)"
afirmar "o container do Loki existe" test -n "$ID_LOKI"
afirmar "o container do Alloy existe" test -n "$ID_ALLOY"

# saude() vem de 01-borda.sh (carregado antes pelo smoke.sh).
afirmar "Loki está saudável (healthcheck em /ready)" test "$(saude "$ID_LOKI")" = healthy
afirmar "Alloy está saudável" test "$(saude "$ID_ALLOY")" = healthy

montagens_alloy="$(docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' "$ID_ALLOY")"
afirmar "o socket do Docker não está montado no Alloy" \
  test "${montagens_alloy/docker.sock/}" = "$montagens_alloy"

# Lista com espaço antes de cada nome, para casar só a rede "proxy" exata.
for id_nome in "$ID_LOKI:Loki" "$ID_ALLOY:Alloy"; do
  redes="$(docker inspect -f '{{range $n, $_ := .NetworkSettings.Networks}} {{$n}} {{end}}' "${id_nome%%:*}")"
  afirmar "o ${id_nome#*:} não está na rede proxy" test "${redes/ proxy /}" = "$redes"
done

# loki_streams LOGQL -> uma linha por stream que a consulta acha nos últimos
# 15 min: "N rotulo=valor rotulo=valor ..." (N = linhas; rótulos em ordem).
loki_streams() {
  curl -s --max-time 10 -G "http://127.0.0.1:3100/loki/api/v1/query_range" \
    --data-urlencode "query=$1" --data-urlencode "since=15m" \
    --data-urlencode "limit=1000" 2>/dev/null |
    python3 -c '
import json, sys
for s in json.load(sys.stdin)["data"]["result"]:
    rotulos = " ".join("%s=%s" % kv for kv in sorted(s["stream"].items()))
    print(len(s["values"]), rotulos)
' 2>/dev/null
}

# achar_streams VARIAVEL LOGQL -> guarda na VARIAVEL o resultado de
# loki_streams; sucesso se a consulta achou algo. Usada com esperar_ate 60
# (descoberta do Alloy a cada 15 s + envio); a VARIAVEL fica com a última
# tentativa mesmo se o tempo estourar.
achar_streams() {
  printf -v "$1" '%s' "$(loki_streams "$2")"
  [ -n "${!1}" ]
}

secao "Logs: linha de um container chega ao Loki com os rótulos"

URL_LOKI_LOCAL="http://127.0.0.1:3100/ready"
loki_responde() {
  [ "$(curl -s --max-time 5 "$URL_LOKI_LOCAL" 2>/dev/null)" = ready ]
}
esperar_ate 30 loki_responde
afirmar "Loki responde em 127.0.0.1:3100 (/ready)" loki_responde

# O "marcador" (testes/sites-extras.yml) é um container comum de um projeto
# de site (traefik-smoke-sites): escreve "marca-logs-07" no stdout e
# "marca-logs-07-erro" no stderr a cada 2 s.
esperar_ate 60 achar_streams R_MARCA '{servico="marcador"} |= "marca-logs-07" != "erro"'
afirmar "a linha marcada (stdout) chegou ao Loki" test -n "$R_MARCA"
afirmar "com projeto=traefik-smoke-sites e servico=marcador" \
  bash -c 'printf "%s\n" "$1" | grep -q " projeto=traefik-smoke-sites servico=marcador "' _ "$R_MARCA"
afirmar "com stream=stdout" \
  bash -c 'printf "%s\n" "$1" | grep -q " stream=stdout\$"' _ "$R_MARCA"

esperar_ate 60 achar_streams R_ERRO '{servico="marcador"} |= "marca-logs-07-erro"'
afirmar "a linha marcada do stderr chegou com stream=stderr" \
  bash -c 'printf "%s\n" "$1" | grep -q " projeto=traefik-smoke-sites servico=marcador stream=stderr\$"' _ "$R_ERRO"

# Cada linha uma vez só (o Alloy vê o container uma vez por rede/porta, mas
# lê o log uma vez por container). As do stdout e do stderr se alternam, e
# o próprio Docker conta as do stdout.
ID_MARCADOR="$(sites ps -q marcador)"
contagens_conferem() {
  local no_loki no_docker
  no_loki="$(loki_streams '{servico="marcador"} |= "marca-logs-07" != "erro"' | awk '{ n += $1 } END { print n + 0 }')"
  no_docker="$(docker logs --since 15m "$ID_MARCADOR" 2>/dev/null | grep -c 'marca-logs-07$')"
  # Margem de 2 linhas: as mais recentes podem ainda não ter sido enviadas.
  [ "$no_loki" -le "$no_docker" ] && [ "$no_loki" -ge $((no_docker - 2)) ]
}
esperar_ate 10 contagens_conferem
afirmar "nenhuma linha duplicada nem perdida (Loki x docker logs)" contagens_conferem

# O socket-proxy registra cada consulta do Alloy à API do Docker; o Alloy
# descarta essas linhas (ruído). Controle positivo: o socket-proxy escreveu
# log (senão a ausência no Loki não provaria nada). Como as linhas do
# marcador já chegaram acima, o Alloy está enviando.
# ID_SOCKET vem de 01-borda.sh.
afirmar "o socket-proxy escreveu log (controle)" \
  test -n "$(docker logs --since 15m "$ID_SOCKET" 2>&1 | head -n 1)"
afirmar "o log do socket-proxy NÃO chega ao Loki (descartado no Alloy)" \
  test -z "$(loki_streams '{servico="socket-proxy"}')"

secao "Logs: Traefik separado em acesso e log próprio"

req https "$HOST_TESTE" /marca-logs-07-acesso
esperar_ate 60 achar_streams R_ACESSO '{tipo="acesso"} |= "/marca-logs-07-acesso"'
afirmar "a requisição gerou linha tipo=acesso" test -n "$R_ACESSO"
# Valor esperado vem do exemplo (traefik.http.routers.whoami) + provedor.
afirmar "a linha de acesso tem router=whoami@docker" \
  bash -c 'printf "%s\n" "$1" | grep -q " router=whoami@docker "' _ "$R_ACESSO"
afirmar "a linha de acesso tem projeto=traefik-smoke-borda e servico=traefik" \
  bash -c 'printf "%s\n" "$1" | grep -q " projeto=traefik-smoke-borda .*servico=traefik "' _ "$R_ACESSO"

# Status, caminho etc. ficam no corpo JSON e saem na consulta (| json).
R_JSON="$(loki_streams '{tipo="acesso"} |= "/marca-logs-07-acesso" | json | DownstreamStatus = 200')"
afirmar "o corpo da linha de acesso é JSON consultável (| json, status 200)" test -n "$R_JSON"

esperar_ate 60 achar_streams R_PROPRIO '{servico="traefik", tipo="traefik"}'
afirmar "o log do próprio Traefik (texto) chega com tipo=traefik" test -n "$R_PROPRIO"
afirmar "o log do próprio Traefik não tem rótulo router" \
  bash -c '! printf "%s\n" "$1" | grep -q " router="' _ "$R_PROPRIO"

# Host inventado (como o de um bot): 404 da borda, sem router. O Host não
# pode virar rótulo em lugar nenhum.
HOST_FORJADO="host-forjado-07.smoke.test"
req https "$HOST_FORJADO" /marca-logs-07-forjado
esperar_ate 60 achar_streams R_FORJADO '{tipo="acesso"} |= "/marca-logs-07-forjado"'
afirmar "requisição sem router também chega como tipo=acesso" test -n "$R_FORJADO"
afirmar "requisição sem router fica sem o rótulo router" \
  bash -c '! printf "%s\n" "$1" | grep -q " router="' _ "$R_FORJADO"
TODOS_ROTULOS="$(curl -s --max-time 10 -G "http://127.0.0.1:3100/loki/api/v1/series" \
  --data-urlencode 'match[]={projeto=~".+"}' --data-urlencode "since=15m" 2>/dev/null)"
afirmar "a consulta de todos os rótulos respondeu" \
  bash -c 'printf "%s" "$1" | grep -q "\"status\":\"success\""' _ "$TODOS_ROTULOS"
afirmar "nenhum rótulo traz o Host da requisição (RequestHost)" \
  bash -c '! printf "%s" "$1" | grep -qiE "host-forjado-07|RequestHost"' _ "$TODOS_ROTULOS"

secao "Logs: Loki só no loopback do host"

PORTAS_LOKI="$(docker port "$ID_LOKI")"
afirmar "Loki publicado apenas em 127.0.0.1:3100" \
  bash -c 'printf "%s\n" "$1" | grep -q "^3100/tcp -> 127.0.0.1:3100$"' _ "$PORTAS_LOKI"
afirmar "Loki sem nenhuma porta fora do loopback" \
  bash -c '! printf "%s\n" "$1" | grep -qE -- "-> (0\.0\.0\.0|\[::\]):"' _ "$PORTAS_LOKI"
afirmar "Alloy sem porta publicada" test -z "$(docker port "$ID_ALLOY")"

# IP_FORA (primeiro IPv4 não-loopback) vem de 06-node-exporter.sh.
if [ -z "${IP_FORA:-}" ]; then
  falha "não responde no IP não-loopback da máquina" "nenhum IPv4 não-loopback encontrado"
elif curl -s --max-time 5 -o /dev/null "http://$IP_FORA:3100/ready" 2>/dev/null; then
  falha "não responde no IP não-loopback da máquina ($IP_FORA:3100)"
else
  ok "não responde no IP não-loopback da máquina ($IP_FORA:3100)"
fi

# Um site vizinho na rede "proxy": nem pelo nome "loki", nem pelo IP do
# container (rede "logs"), nem pelo gateway da rede "proxy" (host).
# GW_PROXY vem de 06-node-exporter.sh.
IP_LOKI="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$ID_LOKI" |
  awk '{ print $1 }')"
for alvo in loki "$IP_LOKI" "${GW_PROXY:-}"; do
  if [ -z "$alvo" ]; then
    falha "Loki não responde a um container vizinho na rede proxy" "alvo vazio (IP ou gateway não encontrado)"
  elif vizinho -q -T 5 -O /dev/null "http://$alvo:3100/ready" >/dev/null 2>&1; then
    falha "Loki não responde a um container vizinho na rede proxy ($alvo:3100)"
  else
    ok "Loki não responde a um container vizinho na rede proxy ($alvo:3100)"
  fi
done

secao "Logs: o Alloy só lê o Docker"

# HTTP cru pelo bash (/dev/tcp): a imagem do Alloy não tem wget nem curl.
# Imprime a linha de status, ex.: "HTTP/1.0 403 Forbidden".
no_alloy_http() {
  docker exec "$ID_ALLOY" bash -c \
    'exec 3<>/dev/tcp/socket-proxy/2375 && printf "%s %s HTTP/1.0\r\n\r\n" "$1" "$2" >&3 && head -n 1 <&3' \
    _ "$1" "$2" 2>/dev/null | tr -d '\r'
}
# Controle positivo: sem ele, uma conexão morta passaria por "recusado".
afirmar "do Alloy, a leitura é permitida (GET /containers/json -> 200)" \
  bash -c '[[ "$1" == *" 200 "* ]]' _ "$(no_alloy_http GET /containers/json)"
afirmar "do Alloy, parar um container é recusado (POST .../stop -> 403)" \
  bash -c '[[ "$1" == *" 403 "* ]]' _ "$(no_alloy_http POST "/containers/$ID_TRAEFIK/stop")"
afirmar "o Traefik continua de pé depois da tentativa" \
  test "$(docker inspect -f '{{.State.Running}}' "$ID_TRAEFIK")" = true
