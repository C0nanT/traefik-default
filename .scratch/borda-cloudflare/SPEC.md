# Borda: só Cloudflare e limite de taxa

Status: ready-for-agent

> **Não commitar esta pasta antes do deploy.** Ela descreve duas falhas ainda abertas num repositório público. Até os dois deploys e a conferência ao vivo, nenhum commit inclui `.scratch/borda-cloudflare/`: adicione só os arquivos que você mudou, nunca `git add -A`, `git add .` ou `git commit -a`. Confira `git status` antes de cada commit. O último ticket commita esta pasta, depois do deploy. Commits e PRs usam texto neutro (por exemplo "peças de borda: só Cloudflare e limite de taxa"), sem dizer que existia uma brecha.
>
> Origem: achados "Origem aceita conexão direta, sem passar pela Cloudflare" e "Rajadas de varredura sem limite de taxa nem bloqueio" do relatório local `/home/conan/projects/homelab-monitoring/revisoes/RELATORIO.md` (seção Segurança).

## Problem Statement

O `conantorres.dev` está atrás da Cloudflare (nuvem laranja), mas a VPS aceita conexão direta nas portas 80 e 443 de qualquer IP. Quem descobre o IP da origem (rDNS, varreduras em massa, histórico de DNS) fala direto com o Traefik e passa por fora do WAF, do limite de taxa e da proteção contra DDoS da Cloudflare. Os logs mostram conexões diretas de fora das faixas da Cloudflare chegando ao roteador do conan-torres com 200.

Além disso, não existe limite de taxa em lugar nenhum. Uma varredura de um único IP mandou quase mil requisições num minuto ao `conantorres.dev` (`.env`, `.git/config`, configurações de nuvem), e cada uma chegou ao Next, que renderizou a página 404. Essas rajadas deixam o site lento e aumentam as chamadas ao YouTube que voltam 429.

Um firewall que deixe 80/443 abertas só para a Cloudflare não serve: o bbcontainer usa DNS fora da Cloudflare e o emissor `le-http`, que precisa da porta 80 aberta para o Let's Encrypt.

## Solution

O `traefik-default` ganha duas peças novas no contrato, que cada site escolhe usar nas labels:

- **`so-cloudflare@file`**: só aceita conexões cujo IP de origem (o IP da conexão TCP, não um cabeçalho) esteja nas faixas da Cloudflare. Qualquer outra recebe 403.
- **`limite-taxa@file`**: limita cada visitante a uma média de 5 requisições por segundo, com rajada de 100. Acima disso, 429. O visitante é identificado pelo IP real (o item mais à direita do `X-Forwarded-For` que não seja da Cloudflare), não pelo IP do servidor da Cloudflare.

As duas peças vêm da mesma lista de faixas da Cloudflare que já existe no `traefik.yml` (`trustedIPs`). Assim, atualizar as faixas atualiza tudo de uma vez.

O conan-torres liga as duas peças nos roteadores `conan-torres` e `conan-torres-www`. Sites que não pedem as peças, como o bbcontainer, não mudam em nada.

## User Stories

1. Como dono do `conantorres.dev`, quero que uma conexão direta na origem receba 403, para que ninguém contorne a proteção da Cloudflare.
2. Como dono do `conantorres.dev`, quero que o tráfego normal pela Cloudflare continue respondendo 200, para que os visitantes não percebam nada.
3. Como dono do `conantorres.dev`, quero que um IP que manda centenas de requisições por minuto receba 429 na maior parte delas, para que a varredura não deixe o site lento nem chegue ao Next.
4. Como visitante real, quero carregar uma página com dezenas de arquivos de uma vez sem receber 429, para navegar sem notar o limite.
5. Como visitante real atrás da Cloudflare, quero que meu limite seja só meu, e não dividido com todo mundo que passa pelo mesmo servidor da Cloudflare, para não ser bloqueado pelo tráfego dos outros.
6. Como dono da borda, quero que um `X-Forwarded-For` forjado não mude quem o limite de taxa conta, para que o atacante não ganhe um balde novo a cada requisição.
7. Como dono da borda, quero que a peça `so-cloudflare` olhe o IP da conexão, e não um cabeçalho, para que ela não possa ser forjada.
8. Como dono da borda, quero que a lista de faixas da Cloudflare exista num lugar só, para que uma atualização das faixas não fique pela metade.
9. Como dono do bbcontainer, quero que o site continue funcionando exatamente como hoje (sem 403, sem 429, `le-http` renovando), para que a mudança da borda não me afete.
10. Como dono de qualquer site plugado, quero que as peças sejam opcionais e citadas por nome nas labels, como `seguranca@file`, para escolher o que uso.
11. Como quem pluga um site novo, quero que o guia de integração explique quando usar cada peça (só com nuvem laranja para `so-cloudflare`), para não derrubar um site com nuvem cinza.
12. Como dono da borda, quero que o smoke test prove os 403, os 429 e que sites sem as peças seguem com 200, para mudar a borda com segurança no futuro.
13. Como dono da borda, quero que o smoke test confira que a peça gerada traz as mesmas faixas do `trustedIPs`, para pegar uma extração quebrada.
14. Como dono da borda, quero que uma falha ao ler as faixas na partida seja avisada no log e feche só os sites que usam as peças, sem abrir para todos, para que um erro nunca libere a origem.
15. Como dono do `conantorres.dev`, quero que o deploy da borda venha antes das labels do site, para que o roteador nunca cite uma peça que ainda não existe e derrube o site.
16. Como dono dos repositórios públicos, quero commits e PRs com texto neutro, para não anunciar a falha antes do deploy.
17. Como dono, quero um registro privado no `notes` depois do deploy, para lembrar o que foi corrigido e quando.
18. Como dono, quero uma conferência ao vivo única depois dos deploys (conexão direta dá 403, rajada pela Cloudflare dá 429, site normal dá 200), para confirmar a correção em produção.

## Implementation Decisions

- **Geração das peças na partida.** O script de partida do Traefik, que já gera o roteador do painel no diretório `gerado/` (tmpfs), passa a gerar também um arquivo com as duas peças. Ele extrai a lista de faixas do bloco `trustedIPs` (âncora `ips_cloudflare`) do `traefik.yml` montado no contêiner. A extração roda no shell da imagem do Traefik (busybox), sem dependência nova.
- **Falha na extração.** Se a lista sair vazia, o script escreve um AVISO no stderr e gera `so-cloudflare` aceitando só `127.0.0.1/32`, no mesmo padrão "fecha em vez de abrir" do painel. Os sites que usam a peça passam a responder 403. Os outros não mudam. O Traefik sobe normalmente.
- **`so-cloudflare`.** É um middleware `ipAllowList` com `sourceRange` igual às faixas da Cloudflare e sem `ipStrategy`: confere o IP da conexão, que não dá para forjar. A resposta a quem é barrado é o 403 padrão do Traefik.
- **`limite-taxa`.** É um middleware `rateLimit` com média de 5 req/s, rajada de 100 e período de 1 s. O `sourceCriterion.ipStrategy.excludedIPs` usa as mesmas faixas da Cloudflare, para que o visitante seja o IP mais à direita do `X-Forwarded-For` fora da Cloudflare. Quando a conexão não vem de um IP confiável, a entrada descarta o `X-Forwarded-For` (`forwardedHeaders.trustedIPs`), e o limite conta pelo IP da conexão. O estado fica na memória do Traefik e zera quando ele reinicia.
- **Contrato.** Os nomes `so-cloudflare` e `limite-taxa` entram no contrato da borda, ao lado de `seguranca`, `compressao` e `www-para-raiz`. Ficam na tabela de peças do guia de integração e no README, com o aviso de que `so-cloudflare` só serve para sites com nuvem laranja.
- **conan-torres.** Os roteadores `conan-torres` e `conan-torres-www` ganham `so-cloudflare@file` e `limite-taxa@file`, nesta ordem e antes das peças que já usam. A ordem faz um bloqueio ser decidido antes de qualquer trabalho. É uma mudança só de labels, em outro repositório e num PR próprio.
- **Ordem do deploy.**
  1. Merge e deploy do `traefik-default` na VPS (gate humano).
  2. Conferir que as peças aparecem na API do painel.
  3. Merge e deploy do PR do conan-torres (gate humano).

  As labels nunca chegam à produção antes das peças.
- **Sigilo.** Commits e PRs neutros. A pasta `.scratch/borda-cloudflare/` só é commitada no último ticket, depois da conferência ao vivo. O registro privado vai para o repositório `notes`.
- **Conferência ao vivo, pré-autorizada uma única vez.** Depois dos dois deploys:
  1. Do PC do dono, que fica fora da Cloudflare: `curl --resolve conantorres.dev:443:<IP da VPS>` deve dar 403.
  2. Cerca de 150 requisições rápidas, pela Cloudflare, a um caminho inexistente devem mostrar 429.
  3. A home pela Cloudflare deve continuar respondendo 200.

## Testing Decisions

- Um bom teste olha só o comportamento de fora: status HTTP, cabeçalhos e a API do painel. Nunca o conteúdo do arquivo gerado nem detalhes do script.
- **Seam 1: smoke test da borda.** É o `testes/smoke.sh`, com um arquivo novo em `testes/verificacoes/`, e sobe a borda inteira. Entram dois sites de teste novos no `sites-extras.yml`, um com `so-cloudflare@file` e outro com `limite-taxa@file`. O teste confere:
  - o site com `so-cloudflare` responde 403 à conexão do host, que está fora das faixas da Cloudflare;
  - o site com `limite-taxa` responde 429 depois de uma rajada acima de 100;
  - variar o `X-Forwarded-For` forjado entre as requisições não evita o 429;
  - o whoami, sem as peças, continua com 200;
  - as duas peças aparecem na API do painel (127.0.0.1:8080), com `sourceRange` e `excludedIPs` iguais à lista do `trustedIPs` do `traefik.yml`.
- **Seam 2: `testes/docs.sh`**, que roda no pre-commit. Confere que o README e o guia de integração citam `so-cloudflare@file` e `limite-taxa@file`, e que o guia avisa que `so-cloudflare` é só para nuvem laranja.
- O caso "conexão vinda de dentro da Cloudflare é aceita" não tem como ser simulado no smoke. Ele fica para a conferência ao vivo.
- As labels do conan-torres não têm seam próprio. São conferidas ao vivo depois do deploy.
- **Prior art:**
  - `05-painel.sh`: ipAllowList conferido de fora e pela API do painel.
  - `02-pecas.sh`: peças `@file` aplicadas ao whoami.
  - `sites-extras.yml`: sites de teste só do smoke.
  - `testes/docs.sh`: funções `tem` e `tem_re`.
  - Os padrões de `CODING_STANDARDS.md` valem: toda espera com limite e nenhum laço aberto.

## Out of Scope

- Firewall da Hetzner ou do host. O bbcontainer depende das portas abertas.
- Regra de limite de taxa no painel da Cloudflare (extra opcional depois).
- Mudar o bbcontainer ou o DNS dele.
- Usar `CF-Connecting-IP` no app do conan-torres (o leitor já foi corrigido em outra spec).
- Atualização automática das faixas da Cloudflare.
- Os outros achados do relatório (502 no deploy, campos do log de acesso, avisos de partida, etc.).

## Further Notes

- A resposta à falha de extração (gerar `so-cloudflare` só com `127.0.0.1/32` e manter o Traefik de pé) foi uma escolha minha, seguindo o padrão do painel. Não chegou a ser discutida.
- Os valores 5 req/s e rajada de 100 vêm do volume medido: uma página carrega dezenas de arquivos, e a varredura de 01/11 chegou a cerca de 16 req/s. Se aparecer 429 para gente de verdade, o primeiro ajuste é a rajada.
- Repositórios envolvidos: `traefik-default` (este, público), `conan-torres` (público, só as labels) e `notes` (privado, registro final).
