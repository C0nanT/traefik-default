# shellcheck shell=bash
# Peça so-cloudflare quando a lista de faixas sai vazia: o Traefik sobe, o
# log mostra o AVISO e a peça fecha (só 127.0.0.1/32) em vez de abrir.
# Carregado pelo testes/smoke.sh; usa as funções de testes/lib.sh e
# IMAGEM_TRAEFIK. Também roda sem a borda de pé: não usa portas do host.
# Dependência do host: jq (lê o JSON da API).
#
# Como: um Traefik avulso, com o mesmo iniciar.sh e as mesmas peças, mas com
# um traefik.yml sem as faixas. Ele roda com --network none: sem rota padrão,
# o painel aceita 127.0.0.1, e a API é lida de dentro do container.

secao "Peça so-cloudflare: lista de faixas vazia fecha a peça"

dir_vazia="$(mktemp -d)"

# traefik_avulso MODELO -> sobe um Traefik sem rede com MODELO como traefik.yml
# e imprime o ID do container.
traefik_avulso() {
  docker run -d --rm --network none --tmpfs /acme --tmpfs /etc/traefik/dynamic/gerado \
    -v "$1:/etc/traefik/modelo/traefik.yml:ro" \
    -v "$RAIZ/traefik/iniciar.sh:/etc/traefik/iniciar.sh:ro" \
    -v "$RAIZ/traefik/dynamic:/etc/traefik/dynamic:ro" \
    --entrypoint /bin/sh "$IMAGEM_TRAEFIK" /etc/traefik/iniciar.sh
}

# api_avulso ID CAMINHO -> corpo da API do Traefik avulso (lida de dentro).
api_avulso() {
  docker exec "$1" wget -q -T 5 -O - "http://127.0.0.1:8080$2" 2>/dev/null
}

# Dois jeitos de a lista sair vazia: a lista existe mas não tem itens, e a
# âncora mudou de nome (o script não acha a lista).
sed -e '/&ips_cloudflare$/,/^    http:$/{/^ *- "/d;}' \
  -e 's/&ips_cloudflare$/\&ips_cloudflare []/' \
  "$RAIZ/traefik/traefik.yml" > "$dir_vazia/sem-itens.yml"
sed -e 's/ips_cloudflare/faixas_renomeadas/g' \
  "$RAIZ/traefik/traefik.yml" > "$dir_vazia/ancora-renomeada.yml"

for caso in sem-itens ancora-renomeada; do
  id_vazia="$(traefik_avulso "$dir_vazia/$caso.yml")"
  afirmar "[$caso] o Traefik sobe (ping responde em até 30 s)" \
    esperar_ate 30 docker exec "$id_vazia" traefik healthcheck --ping
  afirmar "[$caso] o log mostra o AVISO da lista vazia" \
    grep -q 'AVISO.*so-cloudflare' <<<"$(docker logs "$id_vazia" 2>&1)"
  esperar_ate 10 api_avulso "$id_vazia" /api/http/middlewares/so-cloudflare@file
  faixas="$(api_avulso "$id_vazia" /api/http/middlewares/so-cloudflare@file |
    jq -c '.ipAllowList.sourceRange' 2>/dev/null)"
  conferir "[$caso] a peça aceita só 127.0.0.1/32" \
    "sourceRange recebido: '${faixas:-nenhum}'" [ "$faixas" = '["127.0.0.1/32"]' ]
  docker rm -f "$id_vazia" >/dev/null 2>&1
done

rm -rf "$dir_vazia"
