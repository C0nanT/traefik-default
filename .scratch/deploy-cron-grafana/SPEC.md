# Erros do deploy pelo cron no Grafana (e remoção do deploy por SSH)

Status: ready-for-agent

Vale para três repositórios:

- **traefik-default**: a borda e o cron, na VPS.
- **homelab-monitoring**: Prometheus, Grafana e alertas, no PC.
- **conan-torres**: só a remoção do job de deploy.

Substitui a spec `.scratch/deploy-ci/SPEC.md`. O deploy por SSH foi descartado porque exigiria expor a porta 22 da VPS à internet.

## Problem Statement

Os sites da VPS (conantorres.dev e bbcontainer) entram no ar por um cron que, a cada 10 minutos, roda `pull` + `up -d` em cada pasta de `/opt/apps`. Quando um deploy falha, o erro vai só para `/var/log/atualizar-apps.log`, dentro da VPS. Se o cron parar de rodar, nada avisa.

O dono descobre o problema só quando percebe que o site não mudou, e precisa entrar na VPS para ler o log.

Além disso, a tentativa de deploy pelo CI via SSH deixou restos que precisam sair:

- o job de deploy no conan-torres falha a cada push, porque a porta 22 da VPS não é acessível pelo GitHub, e manda e-mail;
- no traefik-default ficaram o workflow, o script e as seções do README e do guia;
- na VPS ficaram o usuário `deploy` e o sudoers;
- no GitHub ficaram o Environment `producao` e os secrets.

## Solution

O cron continua sendo o único caminho de deploy. A cada rodada, ele publica uma métrica por site (falhou ou não) e a hora da rodada, usando o textfile collector do node exporter, o mesmo caminho do disco do Loki. O Prometheus do PC coleta essa métrica pelo túnel, como já faz com o resto.

O Alloy da borda passa a ler o log do cron e manda as linhas para o Loki.

No Grafana, o painel Logs ganha uma linha "Deploy (cron)" com:

- o estado de cada site;
- a hora da última rodada;
- as linhas do log.

Dois alertas novos vão para o Telegram:

- **Deploy falhou (VPS):** dispara já na primeira falha de qualquer site.
- **Cron de deploy parado:** dispara quando passam 30 minutos sem nenhuma rodada.

Tudo do deploy por SSH é removido: código, documentação, a configuração na VPS e a configuração no GitHub.

## User Stories

1. Como dono, quero ser avisado no Telegram quando o deploy de um site falhar, para não descobrir só quando perceber que o site não mudou.
2. Como dono, quero o aviso já na primeira falha, mesmo que a próxima rodada possa se resolver sozinha.
3. Como dono, quero ser avisado quando o cron parar de rodar (nenhuma rodada há 30 minutos), porque um cron parado não gera erro nenhum.
4. Como dono, quero que o alerta diga qual site falhou.
5. Como dono, quero que o alerta de falha se resolva sozinho quando a rodada seguinte der certo, como os outros alertas do homelab.
6. Como dono, quero ver no painel Logs o estado de cada site (ok ou falhou), para saber num relance se os deploys estão em dia.
7. Como dono, quero ver no painel a hora da última rodada do cron.
8. Como dono, quero ver no painel as linhas do log do cron (sites atualizados e erros com a mensagem), para entender a falha sem entrar na VPS.
9. Como dono, quero consultar o log do cron no Explore com LogQL, como os outros logs da borda.
10. Como dono, quero que o bbcontainer também seja coberto, porque o cron atualiza os dois sites. O domínio dele não muda.
11. Como dono, quero que o arquivo de métrica seja gravado de uma vez, para o node exporter nunca ler um arquivo pela metade.
12. Como dono, quero que o cron continue funcionando igual mesmo que a gravação da métrica falhe. A métrica não pode quebrar o deploy.
13. Como dono, quero que, ao instalar a versão nova do script do cron, o README diga que é preciso reinstalá-lo em `/usr/local/bin`. A cópia instalada não se atualiza com o `git pull`.
14. Como dono, quero que o texto do alerta siga o mesmo modelo das mensagens que já existem no Telegram.
15. Como dono, quero que o job de deploy do conan-torres saia, para os pushes na `main` pararem de ficar vermelhos e de mandar e-mail.
16. Como dono, quero que o README e o AGENTS do conan-torres voltem a dizer que o deploy é pelo cron e que `IMAGE_TAG` serve para voltar a uma versão.
17. Como dono, quero que o traefik-default perca o workflow da borda, o script `deploy-vps` com o teste dele e o suporte ao marcador `.deploy-pelo-ci` no cron.
18. Como dono, quero que as seções do README e do guia sobre o deploy pelo CI saiam, e que a seção "Deploy" do guia descreva só o cron e o deploy manual.
19. Como dono, quero que o Dependabot de `github-actions` saia da borda, já que não há mais workflow.
20. Como dono, quero que o `docs.sh` da borda volte a reprovar qualquer arquivo em `.github/workflows`.
21. Como dono, quero um roteiro para remover da VPS o usuário `deploy`, o sudoers e o script instalado.
22. Como dono, quero um roteiro para apagar o Environment `producao` e os secrets dos dois repositórios.
23. Como dono, quero que o HANDOFF registre que o deploy pelo CI foi descartado, com o motivo: não expor a porta 22.
24. Como dono, quero um checklist manual que force uma falha de deploy na VPS e confirme que o alerta chega ao Telegram, e que confirme a volta ao normal.

## Implementation Decisions

- **Métrica do cron.** A cada rodada, o script do cron grava um arquivo `.prom` no volume `textfile` da borda, o mesmo que o node exporter já lê. Ele contém:
  - `deploy_falhou{app="<pasta>"}`: 1 se o `pull` ou o `up` daquele site falhou nesta rodada, 0 se deu certo. Uma série por pasta de `/opt/apps` com compose.
  - um gauge com o horário (Unix) do fim da rodada, para o alerta de cron parado.
  - A gravação é atômica: escreve num arquivo temporário no mesmo volume e renomeia.
  - O cron roda no host. Ele acha o diretório do volume pelo próprio Docker, ou recebe o caminho por variável, que é o que os testes usam. O padrão é o volume real da borda.
  - Se a gravação falhar, o cron registra a falha no log e segue: o deploy nunca depende da métrica.
- **Log do cron no Loki.** O Alloy monta o log do cron só para leitura e o envia ao Loki com um rótulo próprio, por exemplo `job="atualizar-apps"`. O formato do log não muda: data, `atualizado <app>` ou `ERRO <app>: <mensagem>`.
  - O logrotate do log já existe; o Alloy precisa continuar lendo depois da rotação.
- **Prometheus no homelab.** As séries novas já chegam pela coleta do node exporter da VPS, então nenhum job novo é necessário.
- **Alertas no homelab.** São regras provisionadas no mesmo arquivo dos outros alertas, com o mesmo modelo de mensagem:
  - **Deploy falhou (VPS):** `deploy_falhou == 1` em qualquer site, sem período de espera. Usa o rótulo `app` na mensagem. Se resolve quando o valor volta a 0.
  - **Cron de deploy parado:** o horário da última rodada tem mais de 30 minutos. Se a série some, o alerta também dispara. Ele não se confunde com o alerta "Coleta da VPS parada", que já existe: quando a coleta toda para, os dois podem disparar, e isso é aceito.
  - Os limites ficam no mesmo lugar dos outros (`limites`).
- **Painel Logs no homelab.** Ganha uma linha "Deploy (cron)" com:
  - um stat ou tabela por site (ok ou falhou);
  - um stat com a hora da última rodada;
  - um painel de logs com a consulta do rótulo do cron.
- **Remoção do deploy por SSH.**
  - **traefik-default:**
    - sai o workflow da borda;
    - sai o script `deploy-vps`;
    - o teste local é reescrito só para o cron;
    - sai o suporte ao marcador no cron;
    - sai o Dependabot `github-actions`;
    - saem as seções do README "Deploy pelo CI" e "Checklist do primeiro deploy";
    - a seção "Deploy" do guia descreve só o cron e o deploy manual;
    - o `docs.sh` volta a reprovar `.github/workflows` e confere que não sobrou referência a `deploy-vps` nem a `.deploy-pelo-ci`;
    - o HANDOFF fecha o item com "descartado (2026-10-28)" e o motivo.
  - **conan-torres:** o workflow de imagem volta ao que era antes do PR #23, e o README, o AGENTS, o `.env.example` e o compose de produção voltam ao texto do cron. O Claude não faz commit nem push nesse repositório: ele prepara a mudança e o dono commita.
  - **VPS:** passos manuais que o dono roda, no README ou no checklist:
    - remover `/etc/sudoers.d/deploy-vps` e validar com `visudo -c`;
    - `deluser --remove-home deploy`;
    - remover `/usr/local/sbin/deploy-vps`;
    - reinstalar o script do cron.
  - **GitHub:** apagar o Environment `producao` dos dois repositórios, o que apaga junto os secrets.
- **Ordem segura:** primeiro sai o job do conan-torres, que é o que está falhando agora. Depois vem a limpeza da borda e da VPS, e por último a métrica, o log e os alertas.

## Testing Decisions

- Um bom teste olha só o comportamento visível: o conteúdo do arquivo de métrica, as séries no node exporter, as linhas no Loki, o painel e os alertas provisionados no Grafana. Não olha a estrutura interna do script.
- **Seam 1, teste local do cron no traefik-default.** É o teste que já existe, reduzido ao cron. Usa um `docker` de mentira e pastas temporárias, e confere:
  - todos os sites com sucesso: `deploy_falhou` igual a 0 para cada um, mais o horário da rodada;
  - um site falhando: 1 só para ele, e a linha `ERRO` no log;
  - a gravação atômica: nenhum arquivo temporário sobra e o arquivo final é válido;
  - uma falha ao gravar a métrica não muda o resultado do deploy;
  - sem as variáveis de teste, o script usa os caminhos de produção.
- **Seam 2, smoke da borda (existente).** Confere que:
  - o node exporter publica `deploy_falhou` quando há um arquivo de métrica no volume;
  - o Alloy envia ao Loki uma linha escrita no log do cron, com o rótulo próprio.
- **Seam 3, smoke do homelab (existente).** Confere que:
  - o painel Logs tem a linha "Deploy (cron)" com os três painéis;
  - os dois alertas foram provisionados, com os nomes e as consultas esperadas.
- **`docs.sh` dos três repositórios onde existe:**
  - README e guia descrevendo o cron e a métrica;
  - nenhum resto do deploy por SSH;
  - `.github/workflows` vazio na borda.
- **Checklist manual:**
  1. instalar o cron novo na VPS;
  2. ver as séries no Grafana;
  3. forçar uma falha (por exemplo, uma tag inexistente no compose de teste ou `IMAGE_TAG` inválido temporário) e receber o alerta no Telegram;
  4. desfazer a falha e ver o alerta se resolver;
  5. conferir as linhas no painel.
- Modelos:
  - o `disco-loki` que grava `loki_dados_bytes` no volume `textfile`, para a métrica;
  - a verificação `07-logs.sh` da borda, para o Loki;
  - `07-painel-logs.sh` e o `regras.yml` do homelab, para o painel e os alertas.

## Out of Scope

- Deploy pelo CI de qualquer forma: SSH, runner na VPS ou webhook.
- Mudar a frequência do cron ou o fluxo `pull` + `up -d`.
- Rollback automático.
- Alerta por e-mail. Os avisos são só pelo Telegram.
- Mudanças no domínio do bbcontainer.
- Desligar o login por senha no SSH da VPS. Hoje o root só entra por chave, e o resto fica como sugestão futura.

## Further Notes

- **Estado da VPS em 2026-10-28:**
  - o cron já foi reinstalado com a versão que conhece o marcador;
  - o marcador foi removido do conan-torres, que voltou ao cron;
  - o usuário `deploy`, o sudoers e o script ainda estão instalados e devem sair.
- **Estado do GitHub:**
  - o Environment `producao` existe nos dois repositórios, com secrets;
  - o PR #23 está mesclado na `main` do conan-torres, e o job de deploy dele falha por timeout de SSH.
- **Lembrete:** a cópia instalada do script do cron não se atualiza com `git pull`. Toda mudança nele exige o `install` descrito no README.
