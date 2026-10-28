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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- ambiente de cada cenário ------------------------------------------------
# novo_cenario: zera $TMP/cenario com bin/ (docker falso), apps/ e chamadas.log.
# O falso grava "docker <args> @<pasta atual>" no log; FALSO_SAIDA_DOCKER != 0
# faz o docker falhar; FALSO_FALHA_EM=<pasta> faz falhar só naquela pasta.
novo_cenario() {
  CEN="$TMP/cenario"
  rm -rf "$CEN"
  mkdir -p "$CEN/bin" "$CEN/apps"
  : >"$CEN/chamadas.log"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "docker $* @$(basename "$PWD")" >>%q\n' "$CEN/chamadas.log"
    printf '[ "${FALSO_FALHA_EM:-}" = "$(basename "$PWD")" ] && exit 1\n'
    printf 'exit "${FALSO_SAIDA_DOCKER:-0}"\n'
  } >"$CEN/bin/docker"
  chmod +x "$CEN/bin/docker"
}

# site NOME: cria /apps/NOME com docker-compose.yml.
site() {
  mkdir -p "$CEN/apps/$1"
  : >"$CEN/apps/$1/docker-compose.yml"
}

# roda_cron: executa o script do cron com o ambiente de teste.
roda_cron() {
  mkdir -p "$CEN/metricas"
  PATH="$CEN/bin:$PATH" APPS_RAIZ="$CEN/apps" TRAVA_ARQUIVO="$CEN/trava" \
    METRICAS_DIR="${METRICAS_DIR:-$CEN/metricas}" \
    bash vps/atualizar-apps.sh >"$CEN/saida.log" 2>&1
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
  if chamou "compose pull.*@$app\$" && chamou "compose up -d.*@$app\$"; then
    ok "$app recebe pull + up -d"
  else
    falha "$app recebe pull + up -d" "$(cat "$CEN/chamadas.log")"
  fi
done
if chamou '@sem-compose'; then
  falha "pasta sem docker-compose.yml é ignorada" "$(cat "$CEN/chamadas.log")"
else
  ok "pasta sem docker-compose.yml é ignorada"
fi

novo_cenario
site conan-torres
FALSO_SAIDA_DOCKER=1 roda_cron
if grep -q 'ERRO conan-torres' "$CEN/saida.log"; then
  ok "docker que falha vira linha ERRO <site> no log"
else
  falha "docker que falha vira linha ERRO" "$(cat "$CEN/saida.log")"
fi

# Sem as variáveis de ambiente, os caminhos são os de produção.
if grep -qF '${APPS_RAIZ:-/opt/apps}' vps/atualizar-apps.sh \
  && grep -qF '${TRAVA_ARQUIVO:-/run/atualizar-apps.lock}' vps/atualizar-apps.sh; then
  ok "padrões de produção mantidos (/opt/apps e /run/atualizar-apps.lock)"
else
  falha "padrões de produção mantidos" "vps/atualizar-apps.sh"
fi

# --- métrica -----------------------------------------------------------------
echo "== métrica (textfile do node exporter) =="
PROM_CRON="metricas/deploy.prom"

novo_cenario
site bbcontainer
site conan-torres
roda_cron
PROM="$CEN/$PROM_CRON"
if grep -qx 'deploy_falhou{app="bbcontainer"} 0' "$PROM" \
  && grep -qx 'deploy_falhou{app="conan-torres"} 0' "$PROM"; then
  ok "todos ok: deploy_falhou 0 para cada site"
else
  falha "todos ok: deploy_falhou 0 para cada site" "$(cat "$PROM" 2>&1)"
fi
if grep -qE '^deploy_rodada_timestamp_seconds [0-9]{10}$' "$PROM"; then
  ok "grava o horário Unix do fim da rodada"
else
  falha "grava o horário Unix do fim da rodada" "$(cat "$PROM" 2>&1)"
fi
if [ "$(ls "$CEN/metricas")" = "deploy.prom" ]; then
  ok "gravação atômica: nenhum temporário sobrando"
else
  falha "gravação atômica: nenhum temporário sobrando" "$(ls -A "$CEN/metricas")"
fi

novo_cenario
site bbcontainer
site conan-torres
FALSO_FALHA_EM=conan-torres roda_cron
PROM="$CEN/$PROM_CRON"
if grep -qx 'deploy_falhou{app="conan-torres"} 1' "$PROM" \
  && grep -qx 'deploy_falhou{app="bbcontainer"} 0' "$PROM" \
  && grep -q 'ERRO conan-torres' "$CEN/saida.log"; then
  ok "um site falhando: 1 só para ele e linha ERRO no log"
else
  falha "um site falhando: 1 só para ele e linha ERRO no log" "$(cat "$PROM" "$CEN/saida.log" 2>&1)"
fi

# A métrica nunca atrapalha o deploy: diretório impossível de gravar.
novo_cenario
site conan-torres
METRICAS_DIR="$CEN/nao-existe/nem-aqui" roda_cron
codigo=$?
if [ "$codigo" -eq 0 ] \
  && chamou 'compose up -d.*@conan-torres$' \
  && grep -q 'ERRO métrica' "$CEN/saida.log"; then
  ok "falha ao gravar a métrica vira linha no log e não muda o deploy"
else
  falha "falha ao gravar a métrica não muda o deploy" "código $codigo: $(cat "$CEN/saida.log")"
fi

# Sem METRICAS_DIR, o diretório vem do volume real da borda, pelo Docker.
if grep -qF 'docker volume inspect' vps/atualizar-apps.sh \
  && grep -qF '${METRICAS_VOLUME:-traefik_textfile}' vps/atualizar-apps.sh; then
  ok "padrão de produção: mountpoint do volume traefik_textfile"
else
  falha "padrão de produção: mountpoint do volume traefik_textfile" "vps/atualizar-apps.sh"
fi

if [ "$FALHAS" -gt 0 ]; then
  echo "$FALHAS verificação(ões) falharam"
  exit 1
fi
echo "tudo certo"
