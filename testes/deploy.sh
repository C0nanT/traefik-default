#!/usr/bin/env bash
# Teste local do deploy na VPS: o cron e o deploy pelo CI (vps/deploy-vps.sh).
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
  mkdir -p "$CEN/bin" "$CEN/apps" "$CEN/borda"
  : >"$CEN/chamadas.log"
  for cmd in docker git; do
    {
      printf '#!/usr/bin/env bash\n'
      printf 'echo "%s $* @$(basename "$PWD")" >>%q\n' "$cmd" "$CEN/chamadas.log"
      [ "$cmd" = docker ] && cat <<'RESPOSTAS'
# Respostas do docker falso; o cenário escolhe por variáveis FALSO_*.
case "$*" in
  "compose ps -q"*)
    v="FALSO_CONTAINER_${4-}"
    if [ -n "${!v+x}" ]; then echo "${!v}"; else echo "${FALSO_CONTAINER-c0ffee}"; fi ;;
  *"{{.State.Health.Status}}"*)
    v="FALSO_SAUDE_${!#}"
    if [ -n "${!v+x}" ]; then echo "${!v}"; else echo "${FALSO_SAUDE:-healthy}"; fi ;;
  "inspect "*"{{.Image}}"*) echo "${FALSO_ID_EM_USO:-sha256:aaaa}" ;;
  "image inspect "*"{{.Id}}"*) echo "${FALSO_ID_DO_SHA:-sha256:aaaa}" ;;
esac
RESPOSTAS
      [ "$cmd" = git ] && cat <<'RESPOSTAS'
# Respostas do git falso: FALSO_GIT_SUJO = mudança local; o commit muda
# depois do pull; FALSO_SAIDA_PULL != 0 = pull que não é fast-forward.
case "$1" in
  status) echo "${FALSO_GIT_SUJO-}" ;;
  rev-parse)
    if [ -e "$PWD/.pulou" ]; then echo depois222; else echo antes1111; fi ;;
  pull)
    [ "${FALSO_SAIDA_PULL:-0}" -eq 0 ] || exit "$FALSO_SAIDA_PULL"
    : >"$PWD/.pulou" ;;
esac
RESPOSTAS
      printf 'exit "${FALSO_SAIDA_%s:-0}"\n' "${cmd^^}"
    } >"$CEN/bin/$cmd"
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

# roda_deploy PROJETO... : executa o script de deploy com o ambiente de teste.
# O SHA vem de $SHA (vira SSH_ORIGINAL_COMMAND, como no comando forçado);
# $SHA não definido = variável ausente. Guarda o código de saída em $SAIDA
# e a saída em $CEN/saida.log.
roda_deploy() {
  local amb=(PATH="$CEN/bin:$PATH" APPS_RAIZ="$CEN/apps" BORDA_DIR="$CEN/borda" TRAVA_ARQUIVO="$CEN/trava"
    TRAVA_ESPERA="${TRAVA_ESPERA:-2}" PRAZO_SAUDAVEL="${PRAZO_SAUDAVEL:-2}")
  [ -n "${SHA+x}" ] && amb+=(SSH_ORIGINAL_COMMAND="$SHA")
  env -u SSH_ORIGINAL_COMMAND "${amb[@]}" \
    bash vps/deploy-vps.sh "$@" >"$CEN/saida.log" 2>&1
  SAIDA=$?
}

# Um SHA válido (40 caracteres hexadecimais minúsculos).
SHA_OK=0123456789abcdef0123456789abcdef01234567

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

# --- deploy pelo CI: recusas antes de tocar no docker ------------------------
echo "== deploy: entrada =="
# recusado NOME MENSAGEM: código != 0, MENSAGEM (regex) na saída e nenhuma
# chamada ao docker nem ao git.
recusado() {
  if [ "$SAIDA" -ne 0 ] && grep -qiE -- "$2" "$CEN/saida.log" \
    && [ ! -s "$CEN/chamadas.log" ]; then
    ok "$1"
  else
    falha "$1" "saída $SAIDA; $(cat "$CEN/saida.log" "$CEN/chamadas.log")"
  fi
}
novo_cenario; site conan-torres marcador
SHA=$SHA_OK roda_deploy bbcontainer
recusado "projeto fora da lista é recusado sem chamar docker" 'projeto.*não permitido' 
SHA=$SHA_OK roda_deploy
recusado "sem projeto é recusado sem chamar docker" 'uso:' 
SHA=$SHA_OK roda_deploy conan-torres extra
recusado "argumento a mais é recusado sem chamar docker" 'uso:' 

SHA= roda_deploy conan-torres
recusado "SHA vazio é recusado sem chamar docker" 'SHA inválido'
unset SHA
roda_deploy conan-torres
recusado "SHA ausente é recusado sem chamar docker" 'SHA inválido' 
for ruim in "${SHA_OK:1}" "${SHA_OK}0" "${SHA_OK^^}" "${SHA_OK:1}g" \
  "$SHA_OK; id" "$SHA_OK extra" "$SHA_OK"$'\n' '$(id)' '-h'; do
  SHA=$ruim roda_deploy conan-torres
  recusado "SHA '$(printf '%q' "$ruim")' é recusado sem chamar docker" 'SHA inválido'
done

# --- deploy do site ----------------------------------------------------------
echo "== deploy: site =="
# falhou NOME MENSAGEM: código != 0 e MENSAGEM (regex) na saída.
falhou() {
  if [ "$SAIDA" -ne 0 ] && grep -qiE -- "$2" "$CEN/saida.log"; then
    ok "$1"
  else
    falha "$1" "saída $SAIDA; $(cat "$CEN/saida.log")"
  fi
}

novo_cenario; site conan-torres marcador
SHA=$SHA_OK roda_deploy conan-torres
if [ "$SAIDA" -eq 0 ] && chamou 'docker compose pull.*@conan-torres$' \
  && chamou 'docker compose up -d.*@conan-torres$' \
  && chamou "docker pull .*ghcr.io/c0nant/conan-torres:$SHA_OK @" \
  && chamou "docker image rm ghcr.io/c0nant/conan-torres:$SHA_OK @"; then
  ok "caminho feliz: pull + up -d + imagem do SHA conferida (e a tag solta), código 0"
else
  falha "caminho feliz do site" "saída $SAIDA; $(cat "$CEN/saida.log" "$CEN/chamadas.log")"
fi

novo_cenario; site conan-torres marcador
FALSO_SAUDE=starting PRAZO_SAUDAVEL=1 SHA=$SHA_OK roda_deploy conan-torres
falhou "container que não fica healthy no prazo falha com mensagem" 'não ficou healthy'

novo_cenario; site conan-torres marcador
FALSO_CONTAINER= SHA=$SHA_OK roda_deploy conan-torres
falhou "sem container do serviço depois do up falha com mensagem" 'nenhum container'

novo_cenario; site conan-torres marcador
FALSO_ID_EM_USO=sha256:velha FALSO_ID_DO_SHA=sha256:nova SHA=$SHA_OK roda_deploy conan-torres
falhou "digest de latest diferente do da tag do SHA falha com mensagem" 'não é a do commit'

for travada in "IMAGE_TAG=$SHA_OK" "export IMAGE_TAG=abc" "  IMAGE_TAG = abc"; do
  novo_cenario; site conan-torres marcador
  printf 'APP_ENV=production\n%s\n' "$travada" >"$CEN/apps/conan-torres/.env"
  SHA=$SHA_OK roda_deploy conan-torres
  recusado "'$travada' no .env recusa com versão travada, sem pull nem up" 'versão travada'
done
for solta in "# IMAGE_TAG=abc" "IMAGE_TAG=" "OUTRA_IMAGE_TAG=abc"; do
  novo_cenario; site conan-torres marcador
  printf 'APP_ENV=production\n%s\n' "$solta" >"$CEN/apps/conan-torres/.env"
  SHA=$SHA_OK roda_deploy conan-torres
  if [ "$SAIDA" -eq 0 ]; then
    ok "'$solta' no .env não trava o deploy"
  else
    falha "'$solta' no .env não trava o deploy" "saída $SAIDA; $(cat "$CEN/saida.log")"
  fi
done

novo_cenario; site conan-torres marcador
FALSO_SAIDA_DOCKER=1 SHA=$SHA_OK roda_deploy conan-torres
falhou "docker que falha (ex.: login do GHCR expirado) sai != 0 com mensagem" 'ERRO: docker compose pull falhou'

# --- trava compartilhada com o cron ------------------------------------------
echo "== deploy: trava =="
# segura_trava SEGUNDOS: outro processo (o cron, por exemplo) pega a trava em
# segundo plano por SEGUNDOS; volta só quando ela já está presa.
segura_trava() {
  rm -f "$CEN/pronto"
  flock "$CEN/trava" bash -c ': >"$1"; sleep "$2"' _ "$CEN/pronto" "$1" &
  SEGURA=$!
  until [ -e "$CEN/pronto" ]; do sleep 0.1; done
}

novo_cenario; site conan-torres marcador
segura_trava 3
TRAVA_ESPERA=1 SHA=$SHA_OK roda_deploy conan-torres
recusado "trava ocupada além da espera: falha sem chamar docker" 'trava'
wait "$SEGURA"

novo_cenario; site conan-torres marcador
segura_trava 1
TRAVA_ESPERA=5 SHA=$SHA_OK roda_deploy conan-torres
if [ "$SAIDA" -eq 0 ] && chamou 'compose up -d'; then
  ok "trava ocupada por pouco tempo: espera a vez e faz o deploy"
else
  falha "trava ocupada por pouco tempo: espera a vez" "saída $SAIDA; $(cat "$CEN/saida.log")"
fi
wait "$SEGURA"

# --- deploy da borda ---------------------------------------------------------
echo "== deploy: borda =="
# O SHA (SSH_ORIGINAL_COMMAND) não se aplica: ausente ou lixo, tanto faz.
unset SHA
novo_cenario
roda_deploy traefik
if [ "$SAIDA" -eq 0 ] \
  && chamou 'git status.*@borda$' \
  && chamou 'git pull --ff-only.*@borda$' \
  && chamou 'docker compose up -d.*@borda$' \
  && grep -q antes1111 "$CEN/saida.log" && grep -q depois222 "$CEN/saida.log" \
  && [ "$(grep -n 'git pull' "$CEN/chamadas.log" | cut -d: -f1)" -lt \
       "$(grep -n 'compose up' "$CEN/chamadas.log" | cut -d: -f1)" ]; then
  ok "caminho feliz: status, pull --ff-only, up -d, commits de antes e depois no log, código 0"
else
  falha "caminho feliz da borda" "saída $SAIDA; $(cat "$CEN/saida.log" "$CEN/chamadas.log")"
fi
for svc in traefik loki alloy; do
  chamou "docker compose ps -q $svc @borda" \
    || falha "borda espera o serviço $svc" "$(cat "$CEN/chamadas.log")"
done

novo_cenario
SHA='$(id); lixo' roda_deploy traefik
if [ "$SAIDA" -eq 0 ] && ! grep -q lixo "$CEN/saida.log"; then
  ok "SHA em SSH_ORIGINAL_COMMAND é ignorado na borda"
else
  falha "SHA ignorado na borda" "saída $SAIDA; $(cat "$CEN/saida.log")"
fi

novo_cenario
FALSO_GIT_SUJO=" M docker-compose.yml" roda_deploy traefik
recusado_pull() {
  if [ "$SAIDA" -ne 0 ] && grep -qiE -- "$2" "$CEN/saida.log" \
    && ! chamou 'git pull' && ! chamou 'compose up'; then
    ok "$1"
  else
    falha "$1" "saída $SAIDA; $(cat "$CEN/saida.log" "$CEN/chamadas.log")"
  fi
}
recusado_pull "mudança local no git da borda: recusa sem pull nem up" 'mudança local'

novo_cenario
FALSO_SAIDA_PULL=1 roda_deploy traefik
if [ "$SAIDA" -ne 0 ] && grep -qi 'pull.*falhou' "$CEN/saida.log" \
  && ! chamou 'compose up'; then
  ok "pull que não é fast-forward: falha sem up"
else
  falha "pull não fast-forward" "saída $SAIDA; $(cat "$CEN/saida.log" "$CEN/chamadas.log")"
fi

for svc in traefik loki alloy; do
  novo_cenario
  eval "export FALSO_CONTAINER_$svc=c$svc FALSO_SAUDE_c$svc=starting"
  PRAZO_SAUDAVEL=1 roda_deploy traefik
  unset "FALSO_CONTAINER_$svc" "FALSO_SAUDE_c$svc"
  falhou "$svc que não fica healthy no prazo falha com mensagem" "não ficou healthy.*$svc"
done
novo_cenario
FALSO_CONTAINER_loki= PRAZO_SAUDAVEL=1 roda_deploy traefik
falhou "loki sem container depois do up falha com mensagem" 'não ficou healthy.*loki'

# Prazos com zero à esquerda ("08" quebraria a aritmética como octal) ou
# não numéricos são recusados com mensagem.
for ruim in 08 010 abc; do
  novo_cenario
  TRAVA_ESPERA=$ruim roda_deploy traefik
  recusado "TRAVA_ESPERA='$ruim' é recusado sem chamar docker nem git" 'TRAVA_ESPERA inválido'
  novo_cenario
  PRAZO_SAUDAVEL=$ruim roda_deploy traefik
  falhou "PRAZO_SAUDAVEL='$ruim' falha com mensagem" 'PRAZO_SAUDAVEL inválido'
done

novo_cenario
segura_trava 3
TRAVA_ESPERA=1 roda_deploy traefik
recusado "borda: trava ocupada além da espera falha sem chamar docker nem git" 'trava'
wait "$SEGURA"

# Sem as variáveis de ambiente, o deploy usa os caminhos e prazos de produção,
# e a mesma trava do cron.
if grep -qF '${APPS_RAIZ:-/opt/apps}' vps/deploy-vps.sh \
  && grep -qF '${TRAVA_ARQUIVO:-/run/atualizar-apps.lock}' vps/deploy-vps.sh \
  && grep -qF '${BORDA_DIR:-/opt/traefik}' vps/deploy-vps.sh \
  && grep -qF '${PRAZO_SAUDAVEL:-120}' vps/deploy-vps.sh; then
  ok "deploy: padrões de produção (/opt/apps, trava do cron, 120s até healthy)"
else
  falha "deploy: padrões de produção" "vps/deploy-vps.sh"
fi

if [ "$FALHAS" -gt 0 ]; then
  echo "$FALHAS verificação(ões) falharam"
  exit 1
fi
echo "tudo certo"
