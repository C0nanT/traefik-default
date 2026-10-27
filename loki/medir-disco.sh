#!/bin/sh
# Mede o disco usado pelos dados do Loki (volume "loki-dados", montado em
# /loki só para leitura) e deixa o número para o node exporter, que o publica
# junto com as métricas do host (textfile collector). O homelab lê pelo túnel
# da 9100, como o resto: nenhuma porta nova.
#
# Escreve num arquivo temporário e renomeia: o node exporter nunca lê um
# arquivo pela metade. Roda para sempre, a cada INTERVALO segundos.
INTERVALO="${INTERVALO:-300}"
ARQUIVO=/textfile/loki.prom

while true; do
  # du -sk: espaço ocupado no disco (blocos), em KiB.
  if kib="$(du -sk /loki | cut -f1)"; then
    {
      echo "# HELP loki_dados_bytes Disco ocupado pelos dados do Loki (volume loki-dados)."
      echo "# TYPE loki_dados_bytes gauge"
      echo "loki_dados_bytes $((kib * 1024))"
    } > "$ARQUIVO.tmp" && mv "$ARQUIVO.tmp" "$ARQUIVO"
  fi
  sleep "$INTERVALO"
done
