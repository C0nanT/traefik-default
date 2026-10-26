# shellcheck shell=bash
# Verificações do painel/API: só pelo loopback do host (túnel SSH), nunca a
# partir de um container vizinho na rede "proxy".
# Carregado pelo testes/smoke.sh; usa as funções de testes/lib.sh.
#
# Por que importa: os sites vizinhos alcançam traefik:8080 direto pela rede
# "proxy". O router do painel (gerado pelo traefik/iniciar.sh) só aceita a
# origem do túnel; o resto recebe 403.

secao "Painel/API: só pelo túnel SSH"

# Pelo host, como o túnel SSH chega (127.0.0.1:8080 publicado pelo compose).
painel_host() {
  curl -s --max-time 10 -o "$1" -w '%{http_code}' "http://127.0.0.1:8080$2" 2>/dev/null
}
tmp_api="$(mktemp)"
afirmar "pelo loopback do host a API responde 200" \
  test "$(painel_host "$tmp_api" /api/overview)" = 200
afirmar "pelo loopback do host a API traz o JSON das rotas" \
  grep -q '"routers"' "$tmp_api"
afirmar "pelo loopback do host o painel responde 200" \
  test "$(painel_host /dev/null /dashboard/)" = 200
rm -f "$tmp_api"

# status_vizinho CAMINHO [ARGS do wget...] -> imprime o status HTTP que um
# container na rede "proxy" recebe em traefik:8080. Status exato (não só
# "deu erro"), para um erro de rede/DNS não passar por 403.
status_vizinho() {
  local caminho="$1"
  shift
  vizinho -S -O /dev/null "$@" "http://traefik:8080$caminho" 2>&1 |
    awk '/^  HTTP\// { print $2; exit }'
}

for caminho in /api/overview /api/rawdata /dashboard/; do
  afirmar "vizinho na rede proxy recebe 403 em $caminho" \
    test "$(status_vizinho "$caminho")" = 403
done

# O ipAllowList olha o IP da conexão. Cabeçalhos forjados não ajudam.
for cabecalho in "X-Forwarded-For: 127.0.0.1" "X-Real-Ip: 127.0.0.1"; do
  afirmar "vizinho com '$cabecalho' forjado continua com 403" \
    test "$(status_vizinho /api/rawdata --header "$cabecalho")" = 403
done

# O ping (healthcheck) fica livre na mesma porta: prova que a recusa acima é
# do painel, não da rede.
afirmar "vizinho alcança o /ping na mesma porta (a recusa é só do painel)" \
  test "$(status_vizinho /ping)" = 200
