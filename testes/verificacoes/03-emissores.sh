# shellcheck shell=bash
# Verificações dos emissores de certificado (ticket 03).
# Carregado pelo testes/smoke.sh; usa as funções de testes/lib.sh.
#
# O smoke roda SEM token da Cloudflare e sem variáveis ACME (testes/smoke.env):
# o simples fato de a pilha ter subido saudável (verificado em 01-borda.sh)
# já é a regressão "sobe sem token". Aqui conferimos o que dá para ver sem
# emitir certificado de verdade (a emissão real está no checklist do README).

secao "Certificados: armazenamento ACME"

# Sem ACME_AMBIENTE definido, o padrão é staging. Um arquivo por emissor e
# por ambiente; o Traefik cria cada um com permissão 600 ao iniciar.
for emissor in le-dns le-http; do
  arquivo="/acme/$emissor-staging.json"
  perm="$(docker exec "$ID_TRAEFIK" stat -c %a "$arquivo" 2>/dev/null)"
  afirmar "$arquivo existe com permissão 600 (staging é o padrão)" \
    test "$perm" = 600
done

# O diretório /acme vem do host (bind mount de ./acme): é isso que faz os
# certificados sobreviverem a "down -v" e à recriação do container.
origem_acme="$(docker inspect -f \
  '{{range .Mounts}}{{if eq .Destination "/acme"}}{{.Type}}{{end}}{{end}}' \
  "$ID_TRAEFIK")"
afirmar "/acme é um diretório do host (bind), fora do container" \
  test "$origem_acme" = bind
