# shellcheck shell=bash
# Verificações das peças compartilhadas (ticket 02): cabeçalhos de segurança,
# compressão, www -> raiz e TLS mínimo 1.2.
# O whoami (exemplos/whoami) usa as peças via @file.
#
# Dependências do host: curl e openssl (s_client). O teste de TLS 1.1 usa
# "openssl s_client -tls1_1" com SECLEVEL=0, porque o OpenSSL 3 de distros
# modernas se recusa a falar TLS 1.1 por conta própria; sem isso a recusa
# seria do cliente, não do Traefik (falso positivo).

secao "Peças: cabeçalhos de segurança"

req https "$HOST_TESTE" /
afirmar_status "o whoami responde com as peças aplicadas" 200
afirmar_cabecalho_contem "HSTS presente com max-age" Strict-Transport-Security "max-age="
afirmar_cabecalho_contem "HSTS cobre subdomínios" Strict-Transport-Security "includeSubDomains"
afirmar_cabecalho "proteção contra iframe (X-Frame-Options)" X-Frame-Options DENY
afirmar_cabecalho "nosniff (X-Content-Type-Options)" X-Content-Type-Options nosniff
afirmar_cabecalho "referrer policy" Referrer-Policy strict-origin-when-cross-origin

secao "Peças: compressão"

# /data é do whoami e devolve um corpo grande (o Traefik só comprime acima de
# 1 KB). O curl não descomprime sozinho: o cabeçalho é enviado à mão. Só
# status e cabeçalhos importam, então o corpo (binário) é descartado.
req_sem_corpo https "$HOST_TESTE" "/data?size=8&unit=KB" -H "Accept-Encoding: gzip"
afirmar_status "resposta grande do whoami" 200
afirmar_cabecalho "resposta vem comprimida com gzip" Content-Encoding gzip

req_sem_corpo https "$HOST_TESTE" "/data?size=8&unit=KB"
afirmar_status "resposta grande sem Accept-Encoding" 200
afirmar_cabecalho "sem Accept-Encoding a resposta não é comprimida" Content-Encoding ""

secao "Peças: www -> raiz"

req https "www.$HOST_TESTE" "/um/caminho?x=1"
afirmar_status "www redireciona permanentemente" 301 308
afirmar_cabecalho "www leva para a raiz preservando caminho e query" \
  Location "https://$HOST_TESTE/um/caminho?x=1"

secao "Peças: TLS mínimo 1.2 (sem nenhuma label nos sites)"

# openssl s_client não usa --resolve: conecta no IP e manda o SNI.
# </dev/null encerra a sessão logo após o handshake.
tls_handshake() {
  openssl s_client -connect "$IP_TESTE:443" -servername "$HOST_TESTE" \
    "-$1" -cipher 'ALL:@SECLEVEL=0' </dev/null 2>&1
}

if ! openssl s_client -help 2>&1 | grep -q -- '-tls1_1'; then
  falha "openssl s_client precisa suportar -tls1_1 para este teste" \
    "instale um openssl que aceite -tls1_1"
else
  saida_12="$(tls_handshake tls1_2)"
  afirmar "handshake TLS 1.2 é aceito" \
    grep -q -E 'Protocol *: TLSv1\.2|New, TLSv1\.2' <<<"$saida_12"

  saida_11="$(tls_handshake tls1_1)"
  # O alerta vem do servidor. Se o próprio cliente não conseguisse falar
  # TLS 1.1, a saída seria "no protocol available" (não prova nada sobre
  # o Traefik); por isso exigimos o alerta do servidor.
  afirmar "handshake TLS 1.1 é recusado pelo servidor (alert protocol version)" \
    grep -q -i 'alert protocol version' <<<"$saida_11"
fi
