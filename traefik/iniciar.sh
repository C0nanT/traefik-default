#!/bin/sh
# Ponto de entrada do container do Traefik.
#
# POR QUE ISTO EXISTE
# A configuração estática do Traefik vem de UMA fonte só: arquivo, flags de
# linha de comando OU variáveis TRAEFIK_*. Quando existe um arquivo, as outras
# duas são ignoradas em silêncio. E o arquivo YAML não interpreta variáveis
# (um "${VAR}" ali vira o texto literal "${VAR}").
#
# Só que três valores dos emissores (le-dns/le-http) vêm do .env do servidor:
# o ambiente ACME (staging ou produção), o e-mail e, por consequência, os
# arquivos de armazenamento. Então este script:
#   1. lê o modelo comentado (traefik/traefik.yml, montado em
#      /etc/traefik/modelo/traefik.yml);
#   2. troca SÓ os marcadores __ACME_CA_SERVER__, __ACME_EMAIL__ e
#      __ACME_AMBIENTE__ pelos valores do .env;
#   3. grava o resultado em /etc/traefik/traefik.yml (caminho padrão, que
#      também é onde "traefik healthcheck --ping" procura a configuração);
#   4. gera o router do painel/API, que só aceita o túnel SSH (detalhes na
#      seção "PAINEL/API SÓ PELO TÚNEL SSH", mais abaixo);
#   5. gera as peças so-cloudflare e limite-taxa, com as faixas do
#      trustedIPs (seções "PEÇA so-cloudflare" e "PEÇA limite-taxa", mais
#      abaixo);
#   6. vira o processo do Traefik (exec), recebendo os sinais do Docker.
#
# O token da Cloudflare NÃO passa por aqui: o Traefik (biblioteca lego) lê a
# variável CF_DNS_API_TOKEN direto do ambiente do container, e só quando
# precisa emitir/renovar um certificado DNS-01.

set -eu

MODELO=/etc/traefik/modelo/traefik.yml
DESTINO=/etc/traefik/traefik.yml

# Uma única variável escolhe o servidor ACME dos DOIS emissores.
# Padrão seguro: staging (certificados de teste, limites folgados).
ACME_AMBIENTE="${ACME_AMBIENTE:-staging}"
case "$ACME_AMBIENTE" in
  staging)
    ACME_CA_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory" ;;
  producao)
    ACME_CA_SERVER="https://acme-v02.api.letsencrypt.org/directory" ;;
  *)
    echo "iniciar.sh: ACME_AMBIENTE inválido: '$ACME_AMBIENTE' (use staging ou producao)" >&2
    exit 1 ;;
esac

# E-mail é opcional para o Let's Encrypt; vazio também funciona.
ACME_EMAIL="${ACME_EMAIL:-}"

# Validação simples para não quebrar o YAML (o valor fica entre aspas).
case "$ACME_EMAIL" in
  *'"'* | *\\* | *' '*)
    echo "iniciar.sh: ACME_EMAIL inválido: '$ACME_EMAIL'" >&2
    exit 1 ;;
esac

export ACME_AMBIENTE ACME_CA_SERVER ACME_EMAIL

# awk com ENVIRON faz substituição literal (sem regex nos valores), então
# caracteres como "&" ou "/" no e-mail não quebram nada. Só os três
# marcadores são trocados; qualquer outro "$" ou "{{ }}" fica intacto.
awk '
  {
    gsub(/__ACME_CA_SERVER__/, "\001CA\001")
    gsub(/__ACME_EMAIL__/, "\001EMAIL\001")
    gsub(/__ACME_AMBIENTE__/, "\001AMB\001")
    n = split($0, partes, "\001")
    linha = ""
    for (i = 1; i <= n; i++) {
      if (i % 2 == 0) {
        if (partes[i] == "CA") linha = linha ENVIRON["ACME_CA_SERVER"]
        else if (partes[i] == "EMAIL") linha = linha ENVIRON["ACME_EMAIL"]
        else linha = linha ENVIRON["ACME_AMBIENTE"]
      } else {
        linha = linha partes[i]
      }
    }
    print linha
  }
' "$MODELO" > "$DESTINO"

# O Traefik cria cada arquivo de armazenamento com permissão 600 e se recusa
# a usar um arquivo mais aberto. Se um arquivo voltou de backup com outra
# permissão, corrige aqui em vez de deixar o emissor quebrado.
if [ -d /acme ]; then
  chmod 700 /acme
  for arquivo in /acme/*.json; do
    [ -f "$arquivo" ] && chmod 600 "$arquivo"
  done
fi

echo "iniciar.sh: emissores ACME em '$ACME_AMBIENTE' ($ACME_CA_SERVER)"

# ---------------------------------------------------------------------------
# PAINEL/API SÓ PELO TÚNEL SSH
# A porta 8080 (entrada "traefik") é publicada em 127.0.0.1 da VPS, mas os
# sites vizinhos na rede "proxy" também alcançam traefik:8080 direto. Para o
# painel/API só responder a quem vem pelo host, o router abaixo aceita uma
# única origem: o gateway da rede "painel".
#
# Por quê esse IP: uma conexão em 127.0.0.1:8080 do host (o túnel SSH chega
# assim) é repassada pelo Docker ao container a partir do gateway da rede que
# dá a rota padrão ao container. O docker-compose.yml faz da rede "painel"
# (só o Traefik está nela) essa rede, com "gw_priority".
#
# Por que é seguro: um vizinho na rede "proxy" não consegue se passar por
# esse IP. Ele não está na rede "painel"; se forjar o IP de origem, a resposta
# do Traefik vai pela rede "painel" até o host, e a conexão TCP nunca se
# completa. O ipAllowList olha o IP da conexão (não X-Forwarded-For: a
# entrada "traefik" não confia em cabeçalhos encaminhados).
#
# O IP é descoberto aqui (não fixado no compose) porque o Docker escolhe a
# sub-rede de cada rede. Lido de /proc/net/route: na linha da rota padrão
# (destino 00000000), o gateway vem em hexadecimal, bytes invertidos.
# ---------------------------------------------------------------------------
PAINEL_ARQUIVO=/etc/traefik/dynamic/gerado/painel.yml

hex_para_ip() {
  # "0100A8C0" -> "192.168.0.1"
  set -- $(printf '%s' "$1" | sed 's/../& /g')
  printf '%d.%d.%d.%d' "0x$4" "0x$3" "0x$2" "0x$1"
}

GATEWAY_HEX="$(awk '$2 == "00000000" { print $3; exit }' /proc/net/route)"
if [ -n "$GATEWAY_HEX" ]; then
  PAINEL_ORIGEM="$(hex_para_ip "$GATEWAY_HEX")/32"
else
  # Sem rota padrão não há como saber a origem do túnel: fecha o painel em
  # vez de abrir para todos (só o próprio container passa).
  PAINEL_ORIGEM="127.0.0.1/32"
  echo "iniciar.sh: AVISO: sem rota padrão; painel/API fechado (só 127.0.0.1)" >&2
fi

# O diretório gerado/ é um tmpfs (ver docker-compose.yml) dentro das peças,
# que são só leitura. O provedor de arquivo lê subdiretórios na partida.
cat > "$PAINEL_ARQUIVO" <<EOF_PAINEL
# GERADO pelo traefik/iniciar.sh a cada partida. Não edite.
http:
  routers:
    painel:
      # Só na entrada interna "traefik" (:8080). Sem esta lista o router
      # valeria em todas as entradas, inclusive 443.
      entryPoints:
        - traefik
      # Painel (/dashboard/) e API (/api/...). O /ping continua livre (é do
      # healthcheck e não revela nada).
      rule: "PathPrefix(\`/api\`) || PathPrefix(\`/dashboard\`)"
      service: api@internal
      middlewares:
        - painel-so-tunel
  middlewares:
    painel-so-tunel:
      ipAllowList:
        sourceRange:
          - "$PAINEL_ORIGEM"
EOF_PAINEL

echo "iniciar.sh: painel/API aceita só a origem $PAINEL_ORIGEM (túnel SSH)"

# ---------------------------------------------------------------------------
# PEÇA so-cloudflare (SÓ CONEXÕES DA CLOUDFLARE)
# Um site com nuvem laranja pede "so-cloudflare@file" nas labels para só
# aceitar conexões cujo IP de origem esteja nas faixas da Cloudflare (o resto
# recebe 403). Sem ipStrategy: o ipAllowList olha o IP da conexão TCP, que
# não dá para forjar, e não o X-Forwarded-For.
#
# As faixas vêm da MESMA lista do traefik.yml (forwardedHeaders.trustedIPs,
# âncora "ips_cloudflare"): atualizar a lista lá atualiza a peça na próxima
# partida. A leitura pega as linhas '- "faixa"' logo depois da âncora
# (comentários e linhas vazias no meio são pulados) e para na primeira linha
# de outro tipo.
#
# Lista vazia (âncora renomeada, formato mudou...): fecha em vez de abrir. A
# peça aceita só 127.0.0.1/32, os sites que a usam respondem 403 e o resto da
# borda segue normal.
# ---------------------------------------------------------------------------
CLOUDFLARE_ARQUIVO=/etc/traefik/dynamic/gerado/cloudflare.yml

FAIXAS_CLOUDFLARE="$(awk '
  lendo && /^[ \t]*(#|$)/ { next }
  lendo && /^[ \t]*- "[^"]+"[ \t]*$/ {
    sub(/^[ \t]*- "/, ""); sub(/"[ \t]*$/, ""); print; next
  }
  lendo { exit }
  /trustedIPs: &ips_cloudflare[ \t]*$/ { lendo = 1 }
' "$MODELO")"

if [ -z "$FAIXAS_CLOUDFLARE" ]; then
  FAIXAS_CLOUDFLARE="127.0.0.1/32"
  echo "iniciar.sh: AVISO: faixas da Cloudflare não encontradas em trustedIPs (âncora ips_cloudflare); so-cloudflare fechada (só 127.0.0.1)" >&2
fi

# faixas_yaml RECUO -> uma linha '- "faixa"' por faixa, com RECUO na frente.
faixas_yaml() {
  printf '%s\n' "$FAIXAS_CLOUDFLARE" | while IFS= read -r faixa; do
    printf '%s- "%s"\n' "$1" "$faixa"
  done
}

{
  echo "# GERADO pelo traefik/iniciar.sh a cada partida. Não edite."
  echo "http:"
  echo "  middlewares:"
  echo "    so-cloudflare:"
  echo "      ipAllowList:"
  echo "        sourceRange:"
  faixas_yaml "          "
  # PEÇA limite-taxa (LIMITE POR VISITANTE REAL)
  # Média de 5 req/s, rajada de 100, período de 1 s; acima disso, 429. O
  # visitante é o IP mais à direita do X-Forwarded-For que não esteja nas
  # faixas da Cloudflare (excludedIPs = a mesma lista), e não o servidor da
  # Cloudflare que repassou a conexão. Vindo de fora das faixas, a entrada
  # descarta o X-Forwarded-For (forwardedHeaders.trustedIPs) e o limite
  # conta pelo IP da conexão: um cabeçalho forjado não abre um balde novo.
  # O estado fica na memória do Traefik e zera quando ele reinicia.
  echo "    limite-taxa:"
  echo "      rateLimit:"
  echo "        average: 5"
  echo "        burst: 100"
  echo "        period: 1s"
  echo "        sourceCriterion:"
  echo "          ipStrategy:"
  echo "            excludedIPs:"
  faixas_yaml "              "
} > "$CLOUDFLARE_ARQUIVO"

echo "iniciar.sh: so-cloudflare aceita $(printf '%s\n' "$FAIXAS_CLOUDFLARE" | wc -l) faixa(s); limite-taxa ignora as mesmas no X-Forwarded-For"

exec traefik "$@"
