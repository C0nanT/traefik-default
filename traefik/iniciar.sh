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
#   4. vira o processo do Traefik (exec), recebendo os sinais do Docker.
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

exec traefik "$@"
