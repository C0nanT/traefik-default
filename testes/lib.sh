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

# afirmar_cabecalho DESCRICAO NOME VALOR_ESPERADO  (igualdade exata)
afirmar_cabecalho() {
  local desc="$1" nome="$2" esperado="$3" valor
  valor="$(cabecalho "$nome")"
  if [ "$valor" = "$esperado" ]; then
    ok "$desc"
  else
    falha "$desc" "$nome esperado: '$esperado'; recebido: '$valor'"
    return 1
  fi
}

# afirmar_cabecalho_contem DESCRICAO NOME TRECHO
afirmar_cabecalho_contem() {
  local desc="$1" nome="$2" trecho="$3" valor
  valor="$(cabecalho "$nome")"
  if [[ "$valor" == *"$trecho"* ]]; then
    ok "$desc"
  else
    falha "$desc" "$nome deveria conter '$trecho'; recebido: '$valor'"
    return 1
  fi
}

# afirmar_corpo_contem DESCRICAO TRECHO
afirmar_corpo_contem() {
  local desc="$1" trecho="$2"
  if [[ "$RESP_BODY" == *"$trecho"* ]]; then
    ok "$desc"
  else
    falha "$desc" "corpo deveria conter '$trecho'"
    return 1
  fi
}

# afirmar_corpo_nao_contem DESCRICAO TRECHO
afirmar_corpo_nao_contem() {
  local desc="$1" trecho="$2"
  if [[ "$RESP_BODY" != *"$trecho"* ]]; then
    ok "$desc"
  else
    falha "$desc" "corpo não deveria conter '$trecho'"
    return 1
  fi
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
