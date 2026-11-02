# shellcheck shell=bash
# Peça so-cloudflare@file: o site que a pede só aceita conexões vindas das
# faixas da Cloudflare. O host do teste está fora delas, então recebe 403.
# Carregado pelo testes/smoke.sh; usa as funções de testes/lib.sh.
# Dependências do host: curl e jq (lê o JSON da API do painel).
#
# O caso "conexão da Cloudflare é aceita" não dá para simular aqui: fica para
# a conferência ao vivo, depois do deploy.

secao "Peça so-cloudflare: só conexões da Cloudflare"

# A descoberta do site novo é assíncrona: antes dela o Traefik responde 404.
so_cloudflare_roteado() {
  req https "$HOST_SO_CLOUDFLARE" /
  [ "$RESP_STATUS" != 404 ] && [ -n "$RESP_STATUS" ] && [ "$RESP_STATUS" != 000 ]
}
esperar_ate 30 so_cloudflare_roteado

req https "$HOST_SO_CLOUDFLARE" /
afirmar_status "site com so-cloudflare@file recusa a conexão do host (fora da Cloudflare)" 403

# A peça olha o IP da conexão. Um X-Forwarded-For com IP da Cloudflare não ajuda.
req https "$HOST_SO_CLOUDFLARE" / -H "X-Forwarded-For: 173.245.48.1"
afirmar_status "X-Forwarded-For forjado com IP da Cloudflare continua com 403" 403

req https "$HOST_TESTE" /
afirmar_status "o whoami, sem a peça, continua com 200" 200

# A peça na API do painel traz as mesmas faixas que o Traefik leu do
# trustedIPs da entrada websecure (a âncora ips_cloudflare do traefik.yml).
api_painel() {
  curl -s --max-time 10 "http://127.0.0.1:8080$1" 2>/dev/null
}
peca="$(api_painel /api/http/middlewares/so-cloudflare@file)"
entrada="$(api_painel /api/entrypoints/websecure)"
faixas_peca="$(jq -c '.ipAllowList.sourceRange | sort' <<<"$peca" 2>/dev/null)"
faixas_entrada="$(jq -c '.forwardedHeaders.trustedIPs | sort' <<<"$entrada" 2>/dev/null)"
afirmar "a peça aparece habilitada na API do painel" \
  test "$(jq -r '.status' <<<"$peca" 2>/dev/null)" = enabled
# A lista da entrada não pode estar vazia: vazia nos dois lados também seria "igual".
faixas_iguais() {
  [ -n "$faixas_entrada" ] && [ "$faixas_entrada" != null ] &&
    [ "$faixas_entrada" != '[]' ] && [ "$faixas_peca" = "$faixas_entrada" ]
}
conferir "sourceRange da peça igual ao trustedIPs do traefik.yml" \
  "peça: '${faixas_peca:-nenhum}'; trustedIPs: '${faixas_entrada:-nenhum}'" \
  faixas_iguais
