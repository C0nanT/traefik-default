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

# Os containers avulsos levam esta label: a limpeza os acha mesmo se o teste
# for interrompido antes de o ID ser guardado.
ROTULO_AVULSO=traefik-smoke.avulso=lista-vazia

dir_vazia="$(mktemp -d)"
limpar_lista_vazia() {
  docker ps -aq --filter "label=$ROTULO_AVULSO" | xargs -r docker rm -f >/dev/null 2>&1
  rm -rf "$dir_vazia"
}
ao_limpar limpar_lista_vazia

# traefik_avulso MODELO -> sobe um Traefik sem rede com MODELO como traefik.yml
# e imprime o ID do container.
traefik_avulso() {
  docker run -d --rm --network none --label "$ROTULO_AVULSO" \
    --tmpfs /acme --tmpfs /etc/traefik/dynamic/gerado \
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
  if esperar_ate 30 docker exec "$id_vazia" traefik healthcheck --ping; then
    ok "[$caso] o Traefik sobe (ping responde em até 30 s)"
  else
    falha "[$caso] o Traefik sobe (ping responde em até 30 s)" \
      "sem resposta do ping em 30 s; fim do log: $(docker logs --tail 5 "$id_vazia" 2>&1 | tr '\n' ' ')"
  fi
  afirmar "[$caso] o log mostra o AVISO da lista vazia" \
    grep -q 'AVISO.*so-cloudflare' <<<"$(docker logs "$id_vazia" 2>&1)"
  if ! esperar_ate 10 api_avulso "$id_vazia" /api/http/middlewares/so-cloudflare@file; then
    falha "[$caso] a API do Traefik avulso mostra a peça em até 10 s" \
      "GET /api/http/middlewares/so-cloudflare@file sem resposta de sucesso"
  fi
  faixas="$(api_avulso "$id_vazia" /api/http/middlewares/so-cloudflare@file |
    jq -c '.ipAllowList.sourceRange' 2>/dev/null)"
  conferir "[$caso] a peça aceita só 127.0.0.1/32" \
    "sourceRange recebido: '${faixas:-nenhum}'" [ "$faixas" = '["127.0.0.1/32"]' ]
  docker rm -f "$id_vazia" >/dev/null 2>&1
done

limpar_lista_vazia
