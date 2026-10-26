# 04: Logs de acesso e métricas internas

> **Dificuldade:** Médio: **modelo sugerido:** Sonnet (Claude Code) / Sonnet (Cursor). Só sugestão, use o modelo que tiver à mão.

**Spec:** ../SPEC.md

**O que construir:** o Traefik passa a gravar logs de acesso em JSON, com rotação e limite de tamanho pelo driver de log do Docker. Métricas Prometheus ficam ligadas numa entrada interna dedicada, que não é publicada no host (preparação para o Grafana no futuro). O README documenta como acessar o painel e as métricas por túnel SSH.

**Pontos de teste:**
- Smoke test local da pilha

**Bloqueado por:** 01: Pilha mínima de borda com smoke test

Status: ready-for-human

- [x] Uma requisição ao whoami gera uma linha de log de acesso em JSON
- [x] Os logs têm limite de tamanho e quantidade de arquivos
- [x] O smoke test confirma que as métricas não respondem nas portas 80/443
- [x] As métricas respondem dentro da rede interna (verificado pelo smoke test a partir de um container)
- [x] O README tem o comando de túnel SSH para o painel e as métricas
