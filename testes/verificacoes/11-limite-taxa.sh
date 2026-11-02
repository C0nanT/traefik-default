# shellcheck shell=bash
# Peça limite-taxa@file: cada visitante tem média de 5 req/s e rajada de 100;
# acima disso, 429. O host do teste está fora das faixas da Cloudflare, então
# a entrada descarta o X-Forwarded-For e o limite conta pelo IP da conexão.
# Carregado pelo testes/smoke.sh; usa as funções de testes/lib.sh.
# Dependências do host: curl, timeout e jq (lê o JSON da API do painel).
#
# Estado: o balde é da peça no router do site de teste (só ele a pede) e
# fica na memória do Traefik. As rajadas daqui não tocam o whoami nem as
# verificações anteriores; este arquivo roda por último de propósito.
#
# O caso "visitante real atrás da Cloudflare" (X-Forwarded-For vindo de um IP
# da Cloudflare) não dá para simular aqui: fica para a conferência ao vivo.

secao "Peça limite-taxa: limite por visitante"

# Bem acima da rajada de 100: mesmo que a máquina seja lenta, a reposição
# (5 por segundo) não cobre a sobra.
RAJADA=200

# rajada HOST [varia] -> manda RAJADA requisições a HOST numa só chamada do
# curl (a conexão é reaproveitada, então a rajada leva poucos segundos) e
# imprime um status por linha. Com "varia", cada requisição leva um
# X-Forwarded-For forjado diferente. Limite total de 60 s (timeout) e 5 s por
# requisição; status 000 = sem resposta.
rajada() {
  local host="$1" varia="${2:-}" i args=()
  for ((i = 1; i <= RAJADA; i++)); do
    [ "$i" -gt 1 ] && args+=(--next)
    args+=(-sk --max-time 5 --resolve "$host:443:$IP_TESTE" -o /dev/null -w '%{http_code}\n')
    [ -n "$varia" ] && args+=(-H "X-Forwarded-For: 203.0.113.$((i % 250 + 1)), 198.51.100.$((i % 200 + 1))")
    args+=("https://$host:443/")
  done
  timeout 60 curl "${args[@]}" 2>/dev/null
}

# contar STATUS SAIDA -> quantas linhas de SAIDA são STATUS.
contar() {
  grep -cx -- "$1" <<<"$2"
}

# resumo SAIDA -> "N x STATUS" de cada status, para a mensagem de falha.
resumo() {
  sort <<<"$1" | uniq -c | awk '{ printf "%s%s x %s", (NR > 1 ? ", " : ""), $1, $2 }'
}

# A descoberta do site novo é assíncrona: antes dela o Traefik responde 404.
limite_taxa_roteado() {
  req https "$HOST_LIMITE_TAXA" /
  [ "$RESP_STATUS" = 200 ]
}
if ! esperar_ate 30 limite_taxa_roteado; then
  falha "o site com limite-taxa@file responde 200 em até 30 s" \
    "último status: ${RESP_STATUS:-nenhum}"
fi

# 1) Rajada simples: as primeiras passam (cabe a rajada de 100), o resto é 429.
saida="$(rajada "$HOST_LIMITE_TAXA")"
n_ok="$(contar 200 "$saida")"
n_429="$(contar 429 "$saida")"
conferir "rajada de $RAJADA ao site com limite-taxa@file recebe 429" \
  "respostas: $(resumo "$saida")" [ "$n_429" -gt 0 ]
conferir "a rajada de 100 cabe: pelo menos 90 respostas 200 na mesma rajada" \
  "respostas: $(resumo "$saida")" [ "$n_ok" -ge 90 ]

# 2) Logo depois, com o balde vazio: um X-Forwarded-For forjado diferente a
# cada requisição não abre um balde novo. Se abrisse, quase tudo seria 200.
saida="$(rajada "$HOST_LIMITE_TAXA" varia)"
n_429="$(contar 429 "$saida")"
conferir "X-Forwarded-For forjado, diferente a cada requisição, continua com 429" \
  "esperado: mais da metade 429; respostas: $(resumo "$saida")" \
  [ "$n_429" -gt $((RAJADA / 2)) ]

# 3) O whoami não pede a peça: a mesma rajada não recebe nenhum 429.
saida="$(rajada "$HOST_TESTE")"
n_ok="$(contar 200 "$saida")"
conferir "o whoami, sem a peça, responde 200 a toda a rajada de $RAJADA" \
  "respostas: $(resumo "$saida")" [ "$n_ok" -eq "$RAJADA" ]

# 4) A peça na API do painel: média 5, rajada 100, período 1 s e excludedIPs
# igual ao trustedIPs que o Traefik leu da entrada websecure.
api_painel() {
  curl -s --max-time 10 "http://127.0.0.1:8080$1" 2>/dev/null
}
peca="$(api_painel /api/http/middlewares/limite-taxa@file)"
entrada="$(api_painel /api/entrypoints/websecure)"
afirmar "a peça aparece habilitada na API do painel" \
  test "$(jq -r '.status' <<<"$peca" 2>/dev/null)" = enabled
valores="$(jq -c '.rateLimit | [.average, .burst, .period]' <<<"$peca" 2>/dev/null)"
conferir "a peça tem média 5, rajada 100 e período 1s" \
  "[average, burst, period] recebido: '${valores:-nenhum}'" [ "$valores" = '[5,100,"1s"]' ]
faixas_peca="$(jq -c '.rateLimit.sourceCriterion.ipStrategy.excludedIPs | sort' <<<"$peca" 2>/dev/null)"
faixas_entrada="$(jq -c '.forwardedHeaders.trustedIPs | sort' <<<"$entrada" 2>/dev/null)"
# A lista da entrada não pode estar vazia: vazia nos dois lados também seria "igual".
faixas_iguais_limite() {
  [ -n "$faixas_entrada" ] && [ "$faixas_entrada" != null ] &&
    [ "$faixas_entrada" != '[]' ] && [ "$faixas_peca" = "$faixas_entrada" ]
}
conferir "excludedIPs da peça igual ao trustedIPs do traefik.yml" \
  "peça: '${faixas_peca:-nenhum}'; trustedIPs: '${faixas_entrada:-nenhum}'" \
  faixas_iguais_limite
