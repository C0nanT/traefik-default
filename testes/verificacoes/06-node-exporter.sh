# shellcheck shell=bash
# Verificações do node exporter (métricas do host), só no loopback.
# Carregado pelo testes/smoke.sh; usa as funções de testes/lib.sh.

secao "Node exporter: container"

ID_NODE="$(borda ps -q node-exporter)"
afirmar "o container do node exporter existe" test -n "$ID_NODE"

# saude() vem de 01-borda.sh (carregado antes pelo smoke.sh).
afirmar "node exporter está saudável" test "$(saude "$ID_NODE")" = healthy
afirmar "usa a rede do host (network_mode: host), fora da rede proxy" \
  test "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$ID_NODE" 2>/dev/null)" = host
afirmar "enxerga os processos do host (pid: host)" \
  test "$(docker inspect -f '{{.HostConfig.PidMode}}' "$ID_NODE" 2>/dev/null)" = host
afirmar "a raiz do host está montada só para leitura" \
  test "$(docker inspect -f '{{range .Mounts}}{{if eq .Source "/"}}{{.RW}}{{end}}{{end}}' "$ID_NODE" 2>/dev/null)" = false

secao "Node exporter: só no loopback do host"

URL_NODE_LOCAL="http://127.0.0.1:9100/metrics"
CORPO_NODE=""
node_responde() {
  CORPO_NODE="$(curl -s --max-time 5 "$URL_NODE_LOCAL" 2>/dev/null)"
  [[ "$CORPO_NODE" == *node_cpu_seconds_total* ]]
}
esperar_ate 15 node_responde
case "$CORPO_NODE" in
  *node_cpu_seconds_total*) ok "responde em 127.0.0.1:9100 com métricas node_" ;;
  *) falha "responde em 127.0.0.1:9100 com métricas node_" ;;
esac

# Primeiro IPv4 não-loopback da máquina (o "IP público" num servidor).
IP_FORA="$(ip -4 -o addr show scope global 2>/dev/null |
  awk '{ sub(/\/.*/, "", $4); print $4; exit }')"
if [ -z "$IP_FORA" ]; then
  falha "não responde no IP não-loopback da máquina" "nenhum IPv4 não-loopback encontrado"
elif curl -s --max-time 5 -o /dev/null "http://$IP_FORA:9100/metrics" 2>/dev/null; then
  falha "não responde no IP não-loopback da máquina ($IP_FORA:9100)"
else
  ok "não responde no IP não-loopback da máquina ($IP_FORA:9100)"
fi

# Um site vizinho na rede "proxy" chega ao host pelo gateway dessa rede; o
# nome "node-exporter" nem existe nela (o serviço usa a rede do host).
GW_PROXY="$(docker network inspect -f '{{range .IPAM.Config}}{{.Gateway}} {{end}}' proxy 2>/dev/null |
  tr ' ' '\n' | grep -m1 -F .)"
for alvo in "$GW_PROXY" node-exporter; do
  if [ -z "$alvo" ]; then
    falha "não responde de um container vizinho na rede proxy" "gateway da rede proxy não encontrado"
  elif vizinho -q -T 5 -O /dev/null "http://$alvo:9100/metrics" >/dev/null 2>&1; then
    falha "não responde de um container vizinho na rede proxy ($alvo:9100)"
  else
    ok "não responde de um container vizinho na rede proxy ($alvo:9100)"
  fi
done
