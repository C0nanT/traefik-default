#!/usr/bin/env bash
# Teste local do deploy na VPS (cron e, nos próximos tickets, deploy pelo CI).
# Roda sem VPS, sem rede e sem portas: `docker` e `git` de mentira no PATH
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
# novo_cenario: zera $TMP/cenario com bin/ (docker e git falsos), apps/ e
# chamadas.log. Os falsos gravam "<comando> <args> @<pasta atual>" no log.
novo_cenario() {
  CEN="$TMP/cenario"
  rm -rf "$CEN"
  mkdir -p "$CEN/bin" "$CEN/apps"
  : >"$CEN/chamadas.log"
  for cmd in docker git; do
    cat >"$CEN/bin/$cmd" <<FALSO
#!/usr/bin/env bash
echo "$cmd \$* @\$(basename "\$PWD")" >>"$CEN/chamadas.log"
exit "\${FALSO_SAIDA_${cmd^^}:-0}"
FALSO
    chmod +x "$CEN/bin/$cmd"
  done
}

# site NOME [marcador]: cria /apps/NOME com docker-compose.yml (e o marcador).
site() {
  mkdir -p "$CEN/apps/$1"
  : >"$CEN/apps/$1/docker-compose.yml"
  [ "${2:-}" = marcador ] && : >"$CEN/apps/$1/.deploy-pelo-ci"
  return 0
}

# roda_cron: executa o script do cron com o ambiente de teste.
roda_cron() {
  PATH="$CEN/bin:$PATH" APPS_RAIZ="$CEN/apps" TRAVA_ARQUIVO="$CEN/trava" \
    bash vps/atualizar-apps.sh >"$CEN/saida.log" 2>&1
}

chamou() { grep -qE -- "$1" "$CEN/chamadas.log"; }

# --- cron: marcador .deploy-pelo-ci ------------------------------------------
echo "== cron =="
novo_cenario
site com-marcador marcador
site sem-marcador
roda_cron

if chamou 'compose pull.*@sem-marcador' && chamou 'compose up -d.*@sem-marcador'; then
  ok "pasta sem marcador recebe pull + up -d"
else
  falha "pasta sem marcador recebe pull + up -d" "$(cat "$CEN/chamadas.log")"
fi
if chamou '@com-marcador'; then
  falha "pasta com .deploy-pelo-ci é pulada" "$(grep '@com-marcador' "$CEN/chamadas.log")"
else
  ok "pasta com .deploy-pelo-ci é pulada (nenhum pull/up)"
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
