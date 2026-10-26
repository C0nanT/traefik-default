# shellcheck shell=bash
# Verificações de logs de acesso e métricas (ticket 04).
# Carregado pelo testes/smoke.sh; usa as funções de testes/lib.sh.

secao "Logs: acesso em JSON"

# Faz uma requisição marcada para achar a linha com certeza. Só lê o log a
# partir de um instante antes dela (--since), não o histórico inteiro.
INICIO_LOG="$(date +%s)"
req https "$HOST_TESTE" /marca-log-04
LINHA=""
achar_linha_log() {
  LINHA="$(docker logs --since "$INICIO_LOG" "$ID_TRAEFIK" 2>&1 |
    grep '^{' | grep -F '/marca-log-04' | tail -n 1)"
  [ -n "$LINHA" ]
}
esperar_ate 10 achar_linha_log
afirmar "a requisição gerou linha de log de acesso" test -n "$LINHA"
afirmar "a linha de log é JSON válido" \
  bash -c 'printf "%s" "$1" | python3 -c "import json,sys; json.load(sys.stdin)"' _ "$LINHA"
afirmar "o log traz o host e o status" \
  bash -c 'printf "%s" "$1" | grep -qF "\"RequestHost\":\"$2\"" && printf "%s" "$1" | grep -q "\"DownstreamStatus\":200"' _ "$LINHA" "$HOST_TESTE"

secao "Logs: limite de tamanho e quantidade"

afirmar "driver de log json-file" \
  test "$(docker inspect -f '{{.HostConfig.LogConfig.Type}}' "$ID_TRAEFIK")" = json-file
afirmar "max-size definido" \
  test -n "$(docker inspect -f '{{index .HostConfig.LogConfig.Config "max-size"}}' "$ID_TRAEFIK")"
afirmar "max-file definido" \
  test -n "$(docker inspect -f '{{index .HostConfig.LogConfig.Config "max-file"}}' "$ID_TRAEFIK")"

secao "Métricas: dentro da rede, nunca em 80/443"

# Cliente na rede "proxy" (a mesma dos sites). O nome "traefik" resolve pelo
# serviço do compose da borda.
CORPO_METRICAS="$(vizinho -q -O - "http://traefik:8082/metrics" 2>/dev/null)"
afirmar "métricas respondem dentro da rede, a partir de um container" \
  test -n "$CORPO_METRICAS"
case "$CORPO_METRICAS" in
  *traefik_entrypoint_requests_total*) ok "as métricas trazem traefik_entrypoint_requests_total" ;;
  *) falha "as métricas trazem traefik_entrypoint_requests_total" ;;
esac

for esquema in http https; do
  req "$esquema" "" /metrics -L
  afirmar_corpo_nao_contem "$esquema://IP/metrics não expõe métricas" traefik_entrypoint
  req "$esquema" "nao-roteado.smoke.test" /metrics -L
  afirmar_corpo_nao_contem "$esquema://host-qualquer/metrics não expõe métricas" traefik_entrypoint
done

secao "Painel e métricas: só no loopback do host"

PORTAS="$(docker port "$ID_TRAEFIK")"
afirmar "painel publicado apenas em 127.0.0.1" \
  bash -c 'printf "%s\n" "$1" | grep -q "^8080/tcp -> 127.0.0.1:"' _ "$PORTAS"
afirmar "métricas publicadas apenas em 127.0.0.1" \
  bash -c 'printf "%s\n" "$1" | grep -q "^8082/tcp -> 127.0.0.1:"' _ "$PORTAS"
afirmar "nenhuma outra porta fora do loopback além de 80 e 443" \
  bash -c '! printf "%s\n" "$1" | grep -E -- "-> (0\.0\.0\.0|\[::\]):" | grep -Ev "^(80|443)/tcp"' _ "$PORTAS"
