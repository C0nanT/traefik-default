# shellcheck shell=bash
# Verificação do log do cron no Loki (Alloy lê o arquivo, Loki guarda).
# Carregado pelo testes/smoke.sh; usa loki_streams/achar_streams do 07-logs.sh.
#
# O smoke monta uma pasta temporária (LOG_CRON_DIR) no lugar de /var/log/atualizar-apps;
# aqui escrevemos nela uma linha no formato do cron e olhamos o Loki.

secao "Log do cron: linha do arquivo chega ao Loki com o rótulo"

MARCA_CRON="marca-cron-08-$$"
afirmar "a pasta do log do cron existe no host de teste" test -d "$LOG_CRON_DIR"
printf '%s\n' "$(date '+%F %T') $MARCA_CRON atualizado: projeto-teste" \
  >>"$LOG_CRON_DIR/atualizar-apps.log"

esperar_ate 60 achar_streams R_CRON "{job=\"atualizar-apps\"} |= \"$MARCA_CRON\""
afirmar "a linha escrita no log do cron chegou ao Loki" test -n "$R_CRON"
afirmar "com o rótulo job=atualizar-apps" \
  bash -c 'printf "%s\n" "$1" | grep -q "job=atualizar-apps"' _ "$R_CRON"

montagem_cron="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/log-host"}}{{.RW}}{{end}}{{end}}' "$ID_ALLOY")"
afirmar "o Alloy monta o log do cron só leitura" test "$montagem_cron" = false

# Rotação como o logrotate (create): renomeia e recria. O Alloy tem de
# seguir o arquivo novo.
mv "$LOG_CRON_DIR/atualizar-apps.log" "$LOG_CRON_DIR/atualizar-apps.log.1"
: >"$LOG_CRON_DIR/atualizar-apps.log"
MARCA_POS="marca-cron-08-pos-rotacao-$$"
printf '%s\n' "$(date '+%F %T') $MARCA_POS" >>"$LOG_CRON_DIR/atualizar-apps.log"
esperar_ate 60 achar_streams R_POS "{job=\"atualizar-apps\"} |= \"$MARCA_POS\""
afirmar "depois da rotação, a linha do arquivo novo chega ao Loki" test -n "$R_POS"
