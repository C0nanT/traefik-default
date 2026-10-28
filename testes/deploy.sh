#!/usr/bin/env bash
# Teste local do cron de deploy na VPS (vps/atualizar-apps.sh).
# Roda sem VPS, sem rede e sem portas: `docker` de mentira no PATH
# gravam as chamadas num arquivo, e tudo acontece em pastas temporárias.
# Uso: testes/deploy.sh   (sai com código != 0 se alguma verificação falhar)
set -u
RAIZ_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ_REPO" || exit 1

FALHAS=0
ok() { echo "ok    $1"; }
falha() { echo "FALHA $1${2:+ ($2)}"; FALHAS=$((FALHAS + 1)); }
# verifica "descrição" "detalhe se falhar" comando...: ok se o comando sair 0.
verifica() {
  local descricao=$1 detalhe=$2
  shift 2
  if "$@"; then ok "$descricao"; else falha "$descricao" "$detalhe"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- ambiente de cada cenário ------------------------------------------------
# novo_cenario: zera $TMP/cenario com bin/ (docker falso), apps/ e chamadas.log.
# O falso grava "docker <args> @<pasta atual>" no log; FALSO_SAIDA_DOCKER != 0
# faz o docker falhar; FALSO_FALHA_EM=<pasta> faz falhar só naquela pasta;
# FALSO_MSG_ERRO é o texto (com \n) que o docker escreve ao falhar;
# FALSO_MOUNTPOINT é a resposta de `docker volume inspect`.
novo_cenario() {
  CEN="$TMP/cenario"
  rm -rf "$CEN"
  mkdir -p "$CEN/bin" "$CEN/apps"
  : >"$CEN/chamadas.log"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "docker $* @$(basename "$PWD")" >>%q\n' "$CEN/chamadas.log"
    printf '[ "$1 $2" = "volume inspect" ] && { echo "${FALSO_MOUNTPOINT:-}"; exit 0; }\n'
    printf 'if [ "${FALSO_FALHA_EM:-}" = "$(basename "$PWD")" ] || [ "${FALSO_SAIDA_DOCKER:-0}" != 0 ]; then\n'
    printf '  [ -n "${FALSO_MSG_ERRO:-}" ] && printf "%%b\\n" "$FALSO_MSG_ERRO"\n'
    printf '  exit 1\n'
    printf 'fi\n'
  } >"$CEN/bin/docker"
  chmod +x "$CEN/bin/docker"
}

# site NOME: cria /apps/NOME com docker-compose.yml.
site() {
  mkdir -p "$CEN/apps/$1"
  : >"$CEN/apps/$1/docker-compose.yml"
}

# roda_cron: executa o script do cron com o ambiente de teste. O log vai para
# $CEN/saida.log (LOG_ARQUIVO). METRICAS_DIR=<vazio> não é passado: o script
# descobre o diretório pelo docker (padrão de produção).
roda_cron() {
  mkdir -p "$CEN/metricas"
  local metricas=(METRICAS_DIR="${METRICAS_DIR-$CEN/metricas}")
  [ -z "${METRICAS_DIR-x}" ] && metricas=()
  env "${metricas[@]}" PATH="$CEN/bin:$PATH" APPS_RAIZ="$CEN/apps" \
    TRAVA_ARQUIVO="$CEN/trava" LOG_ARQUIVO="${LOG_ARQUIVO:-$CEN/saida.log}" \
    bash vps/atualizar-apps.sh >"$CEN/stdout.log" 2>&1
}

chamou() { grep -qE -- "$1" "$CEN/chamadas.log"; }

# --- cron --------------------------------------------------------------------
echo "== cron =="
novo_cenario
site bbcontainer
site conan-torres
mkdir -p "$CEN/apps/sem-compose"
roda_cron

for app in bbcontainer conan-torres; do
  verifica "$app recebe pull + up -d" "$(cat "$CEN/chamadas.log")" \
    bash -c 'grep -qE -- "compose pull.*@$1\$" "$2" && grep -qE -- "compose up -d.*@$1\$" "$2"' _ "$app" "$CEN/chamadas.log"
done
verifica "pasta sem docker-compose.yml é ignorada" "$(cat "$CEN/chamadas.log")" \
  bash -c '! grep -q "@sem-compose" "$1"' _ "$CEN/chamadas.log"

novo_cenario
site conan-torres
FALSO_SAIDA_DOCKER=1 roda_cron
verifica "docker que falha vira linha ERRO <site> no log" "$(cat "$CEN/saida.log")" \
  grep -q 'ERRO conan-torres' "$CEN/saida.log"

# Erro de várias linhas do docker: uma linha só no log, no formato <data> ERRO <app>: <mensagem>.
novo_cenario
site conan-torres
FALSO_FALHA_EM=conan-torres FALSO_MSG_ERRO='primeira linha\nsegunda linha' roda_cron
verifica "erro de 2 linhas do docker vira uma linha ERRO só" "$(cat "$CEN/saida.log")" \
  grep -qE '^[0-9T:+-]+ ERRO conan-torres: primeira linha segunda linha *$' "$CEN/saida.log"
verifica "o log do erro de 2 linhas tem uma linha só" "$(cat "$CEN/saida.log")" \
  test "$(wc -l <"$CEN/saida.log")" -eq 1

# O script cria a pasta do log se faltar (a do cron: /var/log/atualizar-apps).
novo_cenario
site conan-torres
LOG_ARQUIVO="$CEN/log-novo/atualizar-apps.log" FALSO_SAIDA_DOCKER=1 roda_cron
verifica "cria a pasta do log se faltar e escreve nela" "$(ls -R "$CEN" 2>&1)" \
  grep -q 'ERRO conan-torres' "$CEN/log-novo/atualizar-apps.log"

# Trava: com ela ocupada por outro processo, a rodada sai com 0 sem fazer nada.
# Primeira rodada (docker falhando) deixa linha no log e deploy_falhou 1; a
# segunda, com a trava presa e docker saudável, não pode mudar nada disso.
novo_cenario
site conan-torres
FALSO_SAIDA_DOCKER=1 roda_cron
: >"$CEN/chamadas.log"
cp "$CEN/saida.log" "$CEN/log-antes"
cp "$CEN/metricas/deploy.prom" "$CEN/prom-antes"
rm -f "$CEN/pronto"
flock "$CEN/trava" bash -c ': >"$1"; sleep 5' _ "$CEN/pronto" &
SEGURA=$!
until [ -e "$CEN/pronto" ]; do sleep 0.1; done
# Com docker falhando, uma rodada que passasse da trava deixaria linha ERRO no log.
FALSO_SAIDA_DOCKER=1 roda_cron
roda_cron
codigo=$?
kill "$SEGURA" 2>/dev/null
wait "$SEGURA" 2>/dev/null
verifica "trava ocupada: o script sai com código 0" "código $codigo" \
  test "$codigo" -eq 0
verifica "trava ocupada: docker não é chamado" "$(cat "$CEN/chamadas.log")" \
  test ! -s "$CEN/chamadas.log"
verifica "trava ocupada: o log não ganha linha" "$(cat "$CEN/saida.log")" \
  cmp -s "$CEN/log-antes" "$CEN/saida.log"
verifica "trava ocupada: a métrica da rodada anterior fica idêntica" "$(cat "$CEN/metricas/deploy.prom")" \
  cmp -s "$CEN/prom-antes" "$CEN/metricas/deploy.prom"

# --- métrica -----------------------------------------------------------------
echo "== métrica (textfile do node exporter) =="
PROM_CRON="metricas/deploy.prom"

novo_cenario
site bbcontainer
site conan-torres
roda_cron
PROM="$CEN/$PROM_CRON"
for app in bbcontainer conan-torres; do
  verifica "todos ok: deploy_falhou 0 para $app" "$(cat "$PROM" 2>&1)" \
    grep -qx "deploy_falhou{app=\"$app\"} 0" "$PROM"
done
verifica "grava o horário Unix do fim da rodada" "$(cat "$PROM" 2>&1)" \
  grep -qE '^deploy_rodada_timestamp_seconds [0-9]{10}$' "$PROM"
verifica "gravação atômica: nenhum temporário sobrando" "$(ls -A "$CEN/metricas")" \
  test "$(ls "$CEN/metricas")" = "deploy.prom"

novo_cenario
site bbcontainer
site conan-torres
FALSO_FALHA_EM=conan-torres roda_cron
PROM="$CEN/$PROM_CRON"
verifica "um site falhando: 1 só para ele" "$(cat "$PROM" 2>&1)" \
  grep -qx 'deploy_falhou{app="conan-torres"} 1' "$PROM"
verifica "um site falhando: o outro segue 0" "$(cat "$PROM" 2>&1)" \
  grep -qx 'deploy_falhou{app="bbcontainer"} 0' "$PROM"
verifica "um site falhando: linha ERRO no log" "$(cat "$CEN/saida.log")" \
  grep -q 'ERRO conan-torres' "$CEN/saida.log"

# Rótulo app com \ e " é escapado no .prom (nome de pasta é entrada do host).
novo_cenario
site 'a"b\c'
roda_cron
verifica "rótulo app escapa \\ e \" no .prom" "$(cat "$CEN/$PROM_CRON" 2>&1)" \
  grep -qxF 'deploy_falhou{app="a\"b\\c"} 0' "$CEN/$PROM_CRON"

# A métrica nunca atrapalha o deploy: diretório impossível de gravar.
novo_cenario
site conan-torres
METRICAS_DIR="$CEN/nao-existe/nem-aqui" roda_cron
codigo=$?
verifica "gravar a métrica falhando não muda o deploy (código 0 e up -d)" "código $codigo" \
  bash -c '[ "$1" -eq 0 ] && grep -qE -- "compose up -d.*@conan-torres\$" "$2"' _ "$codigo" "$CEN/chamadas.log"
verifica "falha ao gravar a métrica vira linha ERRO métrica no log" "$(cat "$CEN/saida.log")" \
  grep -q 'ERRO métrica' "$CEN/saida.log"

# Sem METRICAS_DIR, o diretório vem do volume real da borda, pelo Docker.
novo_cenario
site conan-torres
mkdir -p "$CEN/volume-textfile"
FALSO_MOUNTPOINT="$CEN/volume-textfile" METRICAS_DIR= roda_cron
verifica "padrão de produção: deploy.prom no mountpoint do volume traefik_textfile" "$(cat "$CEN/chamadas.log"; ls -A "$CEN/volume-textfile")" \
  test -f "$CEN/volume-textfile/deploy.prom"
verifica "padrão de produção: pergunta ao docker pelo volume traefik_textfile" "$(cat "$CEN/chamadas.log")" \
  grep -q 'volume inspect.*traefik_textfile' "$CEN/chamadas.log"

if [ "$FALHAS" -gt 0 ]; then
  echo "$FALHAS verificação(ões) falharam"
  exit 1
fi
echo "tudo certo"
