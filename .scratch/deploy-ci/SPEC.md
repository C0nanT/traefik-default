> **Substituída (2026-10-28):** o deploy por SSH foi descartado para não expor a porta 22 da VPS. Veja `.scratch/deploy-cron-grafana/SPEC.md`. Este documento fica só como histórico.

# Deploy pelo CI via SSH (traefik-default e conantorres.dev)

Status: ready-for-agent

Vale para dois repositórios: **traefik-default** (a borda, na VPS) e **conan-torres** (o site conantorres.dev). O **bbcontainer** fica de fora e continua sendo atualizado pelo cron.

## Problem Statement

Hoje, o deploy dos sites é feito por um cron na VPS. A cada 10 minutos, ele roda `pull` + `up -d` em cada site de `/opt/apps`.

- **Atraso:** um push na `main` leva até 10 minutos para entrar no ar.
- **Falha silenciosa:** se o deploy falha (imagem que não sobe, container que não fica `healthy`, login do GHCR expirado), o erro vai só para um log dentro da VPS. O dono não vê, a menos que entre lá e procure.

A borda é atualizada sempre à mão. O dono entra por SSH, roda `git pull` + `up -d` e confere tudo sozinho, sem registro do que foi aplicado nem quando.

## Solution

**conantorres.dev.** Logo depois de publicar a imagem no GHCR, o próprio workflow entra na VPS por SSH e faz o deploy na hora. Depois confere que o container ficou `healthy` e que está rodando exatamente a imagem do commit, e faz um `curl` na URL pública. Se algo falha, a execução fica vermelha no GitHub e o dono recebe um e-mail. O cron deixa de atualizar esse site.

**Borda.** O deploy continua decidido pelo dono, mas é feito por um botão "Run workflow" no GitHub, sem precisar entrar na VPS. O workflow:

1. atualiza `/opt/traefik` pelo git, só avançando;
2. sobe a pilha;
3. espera Traefik, Loki e Alloy ficarem de pé;
4. confere os dois domínios por fora.

O registro fica no histórico do Actions.

**Acesso do GitHub à VPS.** O GitHub não ganha shell na VPS. Cada repositório tem uma chave SSH que só consegue rodar um script, e só para o próprio projeto.

## User Stories

1. Como dono do conantorres.dev, quero que um push na `main` entre no ar logo depois que a imagem for publicada, para não esperar até 10 minutos.
2. Como dono do conantorres.dev, quero que a execução fique vermelha no GitHub quando o deploy falhar, para não descobrir o problema só entrando na VPS.
3. Como dono, quero receber um e-mail quando um deploy falhar. É a única exceção à regra "avisos só pelo GitHub".
4. Como dono do conantorres.dev, quero que o deploy espere o container ficar `healthy`, para o verde do CI significar que o site subiu de fato.
5. Como dono do conantorres.dev, quero que o deploy confira que o container está rodando a imagem do commit que o CI construiu, para não dar verde com uma imagem velha.
6. Como dono do conantorres.dev, quero que o workflow faça um `curl` em https://conantorres.dev e exija 200, para confirmar o caminho completo pela borda.
7. Como dono do conantorres.dev, quero que o deploy recuse rodar quando houver uma versão travada no `.env` da VPS (`IMAGE_TAG`). Assim o CI não desfaz em silêncio um travamento que fiz de propósito, e a mensagem diz o motivo.
8. Como dono do conantorres.dev, quero que o cron pare de atualizar esse site, para haver um único caminho de deploy e os dois nunca brigarem.
9. Como dono do bbcontainer, quero que nada mude para ele, que segue no cron, porque o projeto está parado.
10. Como dono da borda, quero aplicar uma mudança do traefik-default por um botão no GitHub, para não precisar entrar na VPS e ainda decidir quando aplicar.
11. Como dono da borda, quero que um merge na `main` (inclusive um PR do Dependabot) nunca atualize a VPS sozinho, porque uma config errada do Traefik derruba os dois sites.
12. Como dono da borda, quero que o deploy recuse rodar quando `/opt/traefik` tiver mudança local, para não perder nem misturar uma edição feita à mão na VPS.
13. Como dono da borda, quero que o deploy só avance o git (`--ff-only`), nunca mescle.
14. Como dono da borda, quero ver no log da execução o commit de antes e o de depois, para saber o que reverter se der errado.
15. Como dono da borda, quero que o deploy espere Traefik, Loki e Alloy ficarem de pé, por até 2 minutos.
16. Como dono da borda, quero que o workflow faça `curl` nos dois domínios, conantorres.dev e o do bbcontainer, só leitura, para confirmar que a borda segue servindo os dois sites.
17. Como dono, aceito downtime curto nos sites durante um deploy.
18. Como dono, quero que nada seja desfeito automaticamente. Quando der errado, o conserto é reverter o commit e fazer um deploy novo.
19. Como dono da VPS, quero que o GitHub entre por um usuário próprio (`deploy`), sem shell útil, sem o grupo `docker` e sem túnel nem terminal, para uma chave vazada não virar acesso root.
20. Como dono da VPS, quero uma chave por repositório, cada uma presa ao próprio projeto na linha do `authorized_keys`. Assim a chave de um repositório não consegue fazer deploy do outro.
21. Como dono da VPS, quero que o script de deploy aceite só projetos de uma lista fixa e só um SHA hexadecimal como dado vindo do GitHub, para nada do workflow virar comando.
22. Como dono da VPS, quero que o sudo do usuário `deploy` libere só esse script.
23. Como dono, quero que o GitHub confira a impressão digital da VPS (`known_hosts` guardado em secret), para não mandar a chave a uma máquina falsa.
24. Como dono, quero os secrets do deploy num Environment `producao` do GitHub, liberado só para a `main`, para um workflow de outro branch não conseguir usá-los.
25. Como dono, quero que a chave privada não passe por action de terceiros: o workflow usa o `ssh` do próprio runner.
26. Como dono da borda, quero que o Dependabot também vigie as GitHub Actions do workflow novo: mensal, com espera de 14 dias, num PR só.
27. Como dono da borda, quero que o `docs.sh` continue barrando workflow de auto-merge sem barrar o workflow de deploy.
28. Como dono, quero que o script de deploy fique versionado no traefik-default, ao lado do script do cron, e que o README diga como instalá-lo, junto com o usuário, o sudoers e as chaves.
29. Como dono, quero testar o script de deploy e o cron no meu computador sem VPS, para não descobrir um erro só em produção, num script que roda como root.
30. Como dono, quero um checklist manual para o primeiro deploy de verdade de cada repositório, incluindo uma falha forçada para ver o e-mail chegar.
31. Como dono, quero que o guia de plugar um projeto descreva o deploy pelo CI como ele é, e não mais como evolução futura, e explique quando um site usa o cron e quando usa o CI.
32. Como dono, quero que o item "deploy pelo CI" do HANDOFF fique marcado como fechado, com um resumo do que foi feito.

## Implementation Decisions

- **Mecanismo: SSH com comando forçado.** Descartados:
  - o runner do GitHub instalado na VPS: roda código do workflow dentro da VPS;
  - só um alerta no cron: não é deploy pelo CI.
- **Script de deploy (`deploy-vps`).**
  - Fica versionado no traefik-default, junto do script do cron, e o dono o instala à mão como root.
  - Recebe o nome do projeto como argumento. Quem passa esse argumento é o `command=` do `authorized_keys`, nunca o GitHub.
  - Lê o SHA pelo `SSH_ORIGINAL_COMMAND`, a variável em que o SSH entrega ao comando forçado o que o cliente pediu. Aceita só hexadecimal de tamanho fixo.
  - Lista fixa de projetos: `conan-torres` (pasta do site em `/opt/apps`) e `traefik` (`/opt/traefik`). Qualquer outro nome é recusado.
  - Usa a mesma trava (`flock`) do script do cron, esperando a vez por tempo limitado, para não rodar junto com um deploy manual ou com o cron.
- **Deploy de um site** (`conan-torres`):
  1. Se o `.env` da pasta define `IMAGE_TAG`, recusa sem mexer em nada e diz que a versão está travada.
  2. Faz `pull` + `up -d`.
  3. Espera o container ficar `healthy` (healthcheck da imagem), por até 2 minutos.
  4. Confere que a imagem `latest` em uso tem o mesmo digest que a tag do SHA no GHCR. O compose continua usando `latest`.
  5. Sai com código diferente de zero em qualquer falha, com uma mensagem legível no log do Actions.
- **Deploy da borda** (`traefik`):
  1. Recusa se o git de `/opt/traefik` tiver mudança local. `.env` e `acme/` são ignorados pelo git e não contam.
  2. Imprime o commit atual.
  3. Faz `git pull --ff-only`.
  4. Imprime o commit novo.
  5. Faz `up -d`.
  6. Espera Traefik, Loki e Alloy ficarem de pé, por até 2 minutos.

  O SHA não se aplica: a borda vai até a ponta da `main`.
- **Sem rollback automático** nos dois casos.
- **Cron.** O script do cron pula toda pasta de site que tenha o arquivo-marcador `.deploy-pelo-ci`. A pasta do conan-torres na VPS ganha o marcador. Fora isso, o comportamento não muda, e o bbcontainer segue nele.
- **Usuário e permissões na VPS.**
  - Usuário `deploy` fora do grupo `docker`. Precisa de um shell real (`/bin/sh`): o sshd roda o comando forçado pelo shell do usuário, e com `nologin` nada roda. A restrição vem do `restrict` + `command=`, não do shell. O sudoers mantém `SSH_ORIGINAL_COMMAND` (`env_keep`), senão o SHA não chega ao script.
  - Uma linha no `authorized_keys` por repositório, com `command="sudo <script> <projeto>"` e `restrict` (equivale a `no-pty`, `no-port-forwarding` e o resto).
  - O sudoers libera para `deploy` só o script, só com os dois argumentos permitidos.
  - O usuário `deploy` precisa conseguir puxar do GHCR. Como o script roda como root pelo sudo, usa o `docker login` que já existe para o root.
  - O README documenta tudo isso na seção de instalação da VPS, no mesmo estilo do usuário `metricas`.
- **Workflow do conan-torres.**
  - Um job de deploy depende do `build-push` no mesmo workflow e herda as mesmas condições (só `main`, só depois do CI verde ou de um disparo manual na `main`).
  - Usa o Environment `producao`, com os secrets de host, chave e `known_hosts`.
  - Passos:
    1. grava a chave e o `known_hosts` em arquivos temporários;
    2. roda `ssh` com `StrictHostKeyChecking=yes`, mandando o SHA construído;
    3. faz um `curl` em https://conantorres.dev, exigindo 200.
  - O `concurrency` existente continua pondo os deploys em fila.
- **Workflow da borda (novo).**
  - Disparado só por `workflow_dispatch`, sem gatilho de push nem de PR.
  - Recusa rodar fora da `main`.
  - Usa o Environment `producao` deste repositório, com uma chave própria.
  - Passos:
    1. `ssh` pedindo o deploy da borda;
    2. `curl` em conantorres.dev e no domínio do bbcontainer, só leitura, os dois exigindo resposta de sucesso.
  - Não faz checkout do código: não é preciso.
- **Environment `producao`** em cada repositório, com regra de branch de deploy limitada à `main`. Os secrets são do Environment, não do repositório.
- **Dependabot da borda.** Ganha o ecossistema `github-actions` com a mesma regra das imagens: mensal, `cooldown` de 14 dias, um grupo só, sem auto-merge.
- **`docs.sh` da borda.**
  - A regra "nenhum arquivo em `.github/workflows`" passa a ser "nenhum workflow de auto-merge": nada que mescle PR ou aprove PR do Dependabot.
  - Passa a conferir:
    - o workflow de deploy existe;
    - ele é só manual e usa o Environment `producao`;
    - o Dependabot cobre `github-actions`;
    - o README tem a instalação do usuário `deploy`.
- **Avisos.** E-mail do GitHub para execução que falha, só para os workflows de deploy. A configuração é da conta do dono e fica descrita no checklist; não vai em arquivo do repositório.
- **Documentação.**
  - Seção "Deploy" do guia de plugar um projeto: o CI por SSH passa a ser o caminho principal para sites com o marcador, e o cron continua como opção.
  - README da borda: instalação do script, do usuário, do sudoers e das chaves, e o botão de deploy.
  - README e AGENTS do conan-torres: o deploy agora é pelo CI e o `IMAGE_TAG` trava o deploy.
  - HANDOFF: item 4 fechado.

## Testing Decisions

- Um bom teste olha só o comportamento visível: o código de saída, a mensagem e quais comandos `docker`/`git` foram ou não chamados. Não olha a estrutura interna do script.
- **Seam 1: teste novo do script de deploy e do cron, no traefik-default.**
  - Põe um `docker` e um `git` de mentira no PATH, e cada um responde conforme o cenário (container `healthy` ou não, digest igual ou diferente, git limpo ou sujo).
  - Usa pastas temporárias no lugar de `/opt/apps` e `/opt/traefik`, então o script precisa permitir trocar essas raízes e a trava por variáveis de ambiente, só nos testes.
  - Cobre:
    - recusa de projeto fora da lista;
    - recusa de SHA inválido ou ausente no deploy do site;
    - recusa de versão travada no `.env`, sem chamar `pull` nem `up`;
    - recusa de borda com mudança local, sem chamar `pull`;
    - falha quando o container não fica `healthy` dentro do prazo, com prazo curto no teste;
    - falha quando o digest não bate;
    - caminho feliz do site e da borda, este último imprimindo o commit de antes e o de depois;
    - o cron pula a pasta com `.deploy-pelo-ci` e atualiza as outras.
  - Roda sem VPS, sem rede e sem as portas do smoke.
- **Seam 2: o `docs.sh` do traefik-default, que já existe.**
  - Confere o workflow de deploy (só manual, Environment `producao`, `curl` nos dois domínios).
  - Confere o Dependabot com `github-actions` e a ausência de workflow de auto-merge.
  - Confere a seção do README sobre o usuário `deploy`.
- **Fora dos testes automáticos:** o job de deploy do conan-torres e o caminho SSH de verdade não têm teste local. Ficam no checklist manual:
  1. instalar na VPS;
  2. primeiro deploy do site e da borda;
  3. conferir que a chave de um repositório não faz deploy do outro, nem abre shell ou túnel;
  4. forçar uma falha (por exemplo, `IMAGE_TAG` travado) e ver a execução vermelha e o e-mail;
  5. conferir que o cron deixou de mexer no conan-torres.
- Modelos para os testes:
  - as verificações `tem`/`nao_tem` do `docs.sh`;
  - o estilo de saída `ok`/`FALHA` e os helpers de `testes/lib.sh`.
- O smoke da borda roda uma vez no fim. O comportamento da borda não muda, então ele deve continuar passando igual.

## Out of Scope

- bbcontainer: segue no cron, sem mudança no repositório nem no domínio.
- Rollback automático e fixar a imagem por SHA no compose.
- Deploy automático da borda no push ou no merge.
- Runner do GitHub instalado na VPS, Watchtower e similares.
- Restringir a porta 22 por IP (as faixas do GitHub mudam), e o firewall só com as faixas da Cloudflare (sugestão futura no HANDOFF).
- Avisos pelo Telegram.
- Os demais itens do HANDOFF: backup do SQLite do leitor e do `acme/`, e token da Cloudflare por arquivo.

## Further Notes

- **Estado de hoje:**
  - O conan-torres publica `ghcr.io/c0nant/conan-torres` com as tags `latest` e `<sha>` depois do workflow `CI`.
  - Na VPS, o compose de produção usa `${IMAGE_TAG:-latest}`, e o README do conan-torres manda usar `IMAGE_TAG=<sha>` para voltar uma versão. Daí a recusa da user story 7.
  - O cron atual usa uma trava com `flock -n` e registra os erros num log da VPS.
- **Ordem segura de colocar no ar:**
  1. instalar o script, o usuário, o sudoers e as chaves na VPS;
  2. criar os Environments e os secrets;
  3. pôr o marcador `.deploy-pelo-ci` na pasta do conan-torres;
  4. só então mesclar o job de deploy do conan-torres.

  Sem o passo 3, o cron e o CI fariam deploy do mesmo site. Com a trava compartilhada, isso não quebra, mas o cron esconderia uma falha do CI.
- O usuário `metricas` (`permitopen` no `authorized_keys`) é o modelo de usuário restrito já em uso na VPS.
- O dono roda os comandos na VPS: o agente só escreve o script, os testes e a documentação.
