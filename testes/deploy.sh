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
# faz o docker falhar.
novo_cenario() {
  CEN="$TMP/cenario"
  rm -rf "$CEN"
  mkdir -p "$CEN/bin" "$CEN/apps"
  : >"$CEN/chamadas.log"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "docker $* @$(basename "$PWD")" >>%q\n' "$CEN/chamadas.log"
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
  PATH="$CEN/bin:$PATH" APPS_RAIZ="$CEN/apps" TRAVA_ARQUIVO="$CEN/trava" \
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

if [ "$FALHAS" -gt 0 ]; then
  echo "$FALHAS verificação(ões) falharam"
  exit 1
fi
echo "tudo certo"
