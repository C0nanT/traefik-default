# shellcheck shell=bash
# Funções auxiliares do smoke test. Este arquivo é carregado (source) pelo
# testes/smoke.sh e também fica disponível para os arquivos em
# testes/verificacoes/. Não execute diretamente.
#
# Variáveis esperadas (definidas pelo smoke.sh):
#   HOST_TESTE      domínio do app de exemplo (ex.: whoami.smoke.test)
#   IP_TESTE        IP onde o Traefik escuta (ex.: 127.0.0.1)
#   ID_TRAEFIK      ID do container do Traefik
#   IMAGEM_TRAEFIK  imagem do Traefik em uso (a tag do docker-compose.yml)

FALHAS=0
SUCESSOS=0

# Últimos resultados de req(), lidos pelas asserções.
RESP_STATUS=""
RESP_HEADERS=""
RESP_BODY=""

ok() {
  SUCESSOS=$((SUCESSOS + 1))
  printf '  \033[32mOK\033[0m    %s\n' "$1"
}

falha() {
  FALHAS=$((FALHAS + 1))
  printf '  \033[31mFALHA\033[0m %s\n' "$1"
  if [ -n "${2:-}" ]; then
    printf '        %s\n' "$2"
  fi
}

secao() {
  printf '\n== %s ==\n' "$1"
}

# req ESQUEMA HOST CAMINHO [args extras do curl...]
# Faz uma requisição ao Traefik local forçando a resolução de HOST para
# IP_TESTE (como se o DNS apontasse para a VPS). Aceita o certificado padrão
# do Traefik (-k). Não segue redirecionamentos (passe -L para seguir).
# Preenche RESP_STATUS, RESP_HEADERS e RESP_BODY.
#
# HOST vazio ("") faz a requisição direto ao IP, sem cabeçalho Host de domínio.
req() {
  _req 1 "$@"
}

# req_sem_corpo: igual a req, mas descarta o corpo (RESP_BODY fica vazio).
# Para quando só status e cabeçalhos importam, ex.: corpo comprimido (binário,
# que o bash não guarda numa variável).
req_sem_corpo() {
  _req 0 "$@"
}

_req() {
  local guardar_corpo="$1" esquema="$2" host="$3" caminho="$4"
  shift 4
  local porta=80
  [ "$esquema" = "https" ] && porta=443

  local alvo resolve=()
  if [ -n "$host" ]; then
    alvo="$esquema://$host:$porta$caminho"
    # As duas portas, para que -L (seguir redirecionamento) também resolva.
    resolve=(--resolve "$host:80:$IP_TESTE" --resolve "$host:443:$IP_TESTE")
  else
    alvo="$esquema://$IP_TESTE:$porta$caminho"
  fi

  local tmp_h saida=/dev/null
  tmp_h="$(mktemp)"
  [ "$guardar_corpo" = 1 ] && saida="$(mktemp)"
  RESP_STATUS="$(curl -sk --max-time 10 "${resolve[@]}" \
    -D "$tmp_h" -o "$saida" -w '%{http_code}' "$@" "$alvo" 2>/dev/null)" || true
  RESP_HEADERS="$(tr -d '\r' <"$tmp_h")"
  RESP_BODY=""
  if [ "$saida" != /dev/null ]; then
    RESP_BODY="$(cat "$saida")"
    rm -f "$saida"
  fi
  rm -f "$tmp_h"
}

# cabecalho NOME -> imprime o valor do cabeçalho NOME da última resposta
# (sem diferenciar maiúsculas/minúsculas no nome).
cabecalho() {
  printf '%s\n' "$RESP_HEADERS" |
    awk -v n="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" '
      { split($0, p, ":"); if (tolower(p[1]) == n) { sub(/^[^:]*:[ \t]*/, ""); print; exit } }'
}

# afirmar_status DESCRICAO STATUS_ESPERADO...  (aceita um ou mais valores)
afirmar_status() {
  local desc="$1"
  shift
  local s
  for s in "$@"; do
    if [ "$RESP_STATUS" = "$s" ]; then
      ok "$desc"
      return 0
    fi
  done
  falha "$desc" "status esperado: $*; recebido: ${RESP_STATUS:-nenhum}"
  return 1
}

# conferir DESCRICAO DETALHE_DA_FALHA COMANDO...  -> OK se o comando der certo;
# senão, falha com o detalhe. Base das asserções de cabeçalho e corpo abaixo.
conferir() {
  local desc="$1" detalhe="$2"
  shift 2
  if "$@"; then
    ok "$desc"
  else
    falha "$desc" "$detalhe"
    return 1
  fi
}

# contem TEXTO TRECHO / nao_contem TEXTO TRECHO
contem() { [[ "$1" == *"$2"* ]]; }
nao_contem() { ! contem "$1" "$2"; }

# afirmar_cabecalho DESCRICAO NOME VALOR_ESPERADO  (igualdade exata)
afirmar_cabecalho() {
  local valor
  valor="$(cabecalho "$2")"
  conferir "$1" "$2 esperado: '$3'; recebido: '$valor'" [ "$valor" = "$3" ]
}

# afirmar_cabecalho_contem DESCRICAO NOME TRECHO
afirmar_cabecalho_contem() {
  local valor
  valor="$(cabecalho "$2")"
  conferir "$1" "$2 deveria conter '$3'; recebido: '$valor'" contem "$valor" "$3"
}

# afirmar_corpo_contem DESCRICAO TRECHO
afirmar_corpo_contem() {
  conferir "$1" "corpo deveria conter '$2'" contem "$RESP_BODY" "$2"
}

# afirmar_corpo_nao_contem DESCRICAO TRECHO
afirmar_corpo_nao_contem() {
  conferir "$1" "corpo não deveria conter '$2'" nao_contem "$RESP_BODY" "$2"
}

# afirmar DESCRICAO COMANDO...  -> OK se o comando terminar com sucesso.
afirmar() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    ok "$desc"
  else
    falha "$desc" "comando falhou: $*"
    return 1
  fi
}

# site_responde HOST STATUS  -> faz um GET https em HOST e dá certo se o
# status for STATUS. Para esperar a descoberta de um site (antes dela, 404):
#   esperar_ate 30 site_responde "$HOST" 200
site_responde() {
  req https "$1" /
  [ "$RESP_STATUS" = "$2" ]
}

# painel_api CAMINHO [args extras do curl...]  -> GET na API do painel pelo
# loopback do host (como o túnel SSH chega) e imprime o corpo.
painel_api() {
  local caminho="$1"
  shift
  curl -s --max-time 10 "$@" "http://127.0.0.1:8080$caminho" 2>/dev/null
}

# afirmar_faixas_do_trustedips DESCRICAO JSON_DA_PECA FILTRO_JQ  -> OK se a
# lista que FILTRO_JQ tira da peça for igual (sem ordem) ao trustedIPs que o
# Traefik leu da entrada websecure. A lista da entrada não pode estar vazia:
# vazia nos dois lados também seria "igual".
afirmar_faixas_do_trustedips() {
  local faixas_peca faixas_entrada
  faixas_peca="$(jq -c "$3 | sort" <<<"$2" 2>/dev/null)"
  faixas_entrada="$(painel_api /api/entrypoints/websecure |
    jq -c '.forwardedHeaders.trustedIPs | sort' 2>/dev/null)"
  conferir "$1" "peça: '${faixas_peca:-nenhum}'; trustedIPs: '${faixas_entrada:-nenhum}'" \
    _listas_iguais_nao_vazias "$faixas_peca" "$faixas_entrada"
}
_listas_iguais_nao_vazias() {
  [ -n "$2" ] && [ "$2" != null ] && [ "$2" != '[]' ] && [ "$1" = "$2" ]
}

# Limpezas das verificações: ao_limpar FUNCAO registra uma função que o
# limpar do smoke.sh roda no fim, mesmo se o teste for interrompido.
LIMPEZAS=()
ao_limpar() {
  LIMPEZAS+=("$1")
}
rodar_limpezas() {
  local f
  for f in "${LIMPEZAS[@]}"; do
    "$f" || true
  done
}

# esperar_ate SEGUNDOS COMANDO...  -> repete o comando até dar certo ou estourar o tempo.
esperar_ate() {
  local limite="$1"
  shift
  local fim=$((SECONDS + limite))
  until "$@" >/dev/null 2>&1; do
    [ "$SECONDS" -ge "$fim" ] && return 1
    sleep 1
  done
}
