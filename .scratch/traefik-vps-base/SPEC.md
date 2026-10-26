# Modelo base de Traefik para VPS

Status: ready-for-agent

## Problem Statement

Tenho uma VPS que vai hospedar duas landing pages (bbcontainer e conan-torres) e preciso de um proxy reverso com HTTPS automático na frente delas. Hoje cada projeto resolve isso do seu jeito: o bbcontainer traz labels próprias do Traefik com nomes de rede, entradas e emissor de certificado inventados por ele, e redirecionamentos HTTP→HTTPS e www→raiz duplicados nas labels; o conan-torres nem está preparado para ficar atrás de um proxy (expõe a porta 8080 no host e é construído na própria VPS).

Além disso, no futuro vou configurar outras VPS com outros projetos, e não quero refazer tudo do zero a cada vez nem copiar configurações de um projeto que não foi pensado como padrão. Também quero que o projeto sirva de estudo: entender de verdade como o Traefik, os certificados (inclusive DNS-01) e a segurança funcionam.

Restrição real: o DNS do `bbcontainermodular.com` fica na Squarespace (sem API de DNS) e não pode ser transferido; o DNS do `conantorres.dev` fica na Cloudflare.

## Solution

Um repositório `traefik-default`, público, que é o "modelo de borda" de qualquer VPS minha: clono em `/opt/traefik`, preencho um `.env` local e subo. Ele contém só o Traefik (com um intermediário de acesso ao Docker), toda a configuração comentada para estudo, peças reaproveitáveis (segurança, compressão, redirecionamentos, TLS) e um contrato claro para plugar qualquer projeto.

Cada site continua no próprio repositório e entra no padrão seguindo o guia "como plugar um projeto": imagem privada pronta no GHCR, sem portas no host, na rede `proxy`, com healthcheck e labels curtas que só referenciam as peças compartilhadas.

Certificados funcionam em modelo híbrido: domínios com DNS na Cloudflare usam DNS-01 (com curinga); domínios sem API de DNS usam HTTP-01. Uma única variável alterna entre o ambiente de teste do Let's Encrypt e produção.

Antes de ir para a VPS, ajusto bbcontainer e conan-torres para o novo contrato. Um smoke test local valida o comportamento do modelo e um checklist manual cobre a emissão real de certificados.

## User Stories

1. Como dono de VPS, quero clonar um único repositório e subir o proxy com um comando, para não reconfigurar o Traefik do zero em cada servidor novo.
2. Como dono de VPS, quero que todas as configurações específicas do servidor fiquem num `.env` local não versionado, para que o repositório seja reaproveitável e possa ser público sem expor segredos.
3. Como dono de VPS, quero um `.env.example` documentado, para saber exatamente o que preencher em cada servidor.
4. Como dono de VPS, quero um checklist de preparação do servidor (instalar Docker, liberar só 22/80/443 no firewall, estrutura de pastas), para não esquecer nenhum passo básico.
5. Como dono de VPS, quero uma estrutura padrão de pastas (`/opt/traefik` para o proxy e `/opt/apps/<projeto>` para cada site), para encontrar tudo do mesmo jeito em qualquer servidor.
6. Como estudante, quero a configuração fixa do Traefik num arquivo YAML comentado, para entender o que cada opção faz.
7. Como estudante, quero que as peças compartilhadas fiquem num arquivo de configuração dinâmica separado, recarregado automaticamente, para entender a diferença entre configuração estática e dinâmica.
8. Como visitante, quero ser redirecionado de HTTP para HTTPS automaticamente, para sempre navegar com conexão segura.
9. Como dono de site, quero que o redirecionamento HTTP→HTTPS seja global no Traefik, para não repetir labels em cada projeto.
10. Como visitante, quero que `www.dominio.com` me leve de forma permanente para `dominio.com`, para que exista um único endereço oficial.
11. Como dono de site, quero ativar o redirecionamento www→raiz com uma referência a uma peça compartilhada, para não redefinir regex em cada projeto.
12. Como dono de site, quero cabeçalhos de segurança (HSTS, proteção contra iframe, nosniff, referrer policy) disponíveis como peça compartilhada, para ter boa segurança com uma linha de label.
13. Como dono de site, quero compressão disponível como peça compartilhada, para páginas mais rápidas sem configurar nada no app.
14. Como dono de VPS, quero que o Traefik exija TLS 1.2 ou superior globalmente, para recusar protocolos inseguros em todos os sites sem label.
15. Como dono de VPS, quero que nenhum container fique público sem `traefik.enable=true`, para nunca expor algo por acidente.
16. Como dono de VPS, quero que o Traefik acesse o Docker só para leitura através de um intermediário, para que uma falha no Traefik não dê controle total do servidor.
17. Como dono de VPS, quero que o painel do Traefik não seja acessível pela internet, mas sim por túnel SSH, para reduzir a superfície de ataque.
18. Como dono de domínio na Cloudflare, quero certificados emitidos via DNS-01 com curinga (`dominio` + `*.dominio`), para criar subdomínios sem novos certificados e aprender DNS-01.
19. Como dono de domínio na Squarespace (sem API), quero certificados emitidos via HTTP-01, para ter HTTPS mesmo sem transferir o DNS.
20. Como dono de site, quero escolher o emissor (`le-dns` ou `le-http`) por label, para que cada projeto use o método compatível com seu DNS.
21. Como dono de VPS, quero alternar todos os emissores entre staging e produção com uma única variável, para testar sem bater nos limites do Let's Encrypt.
22. Como dono de VPS, quero que o token da Cloudflare tenha apenas permissão de editar DNS nas zonas escolhidas, para que um vazamento tenha impacto mínimo.
23. Como dono de VPS, quero que o arquivo de certificados (`acme.json`) persista entre reinícios com permissão restrita, para não reemitir certificados à toa e não expor chaves privadas.
24. Como dono de VPS, quero logs de acesso em JSON com limite de tamanho, para investigar problemas sem encher o disco.
25. Como dono de VPS que vai usar Grafana no futuro, quero métricas Prometheus já ligadas numa porta interna não publicada, para só plugar o coletor depois.
26. Como dono de VPS, quero a versão do Traefik fixada, para que atualizações só aconteçam quando eu decidir.
27. Como dono de VPS, quero o próprio Traefik com healthcheck e política de reinício, para que ele volte sozinho após reboot ou falha.
28. Como dono de site, quero um guia "como plugar um projeto" com um exemplo de compose completo, para adicionar sites novos sem consultar documentação externa.
29. Como dono de site, quero que o guia exija imagem pronta no GHCR construída no CI, para que a VPS nunca compile código.
30. Como dono de site, quero que o guia exija não publicar portas no host e entrar na rede `proxy`, para que todo tráfego passe pelo Traefik.
31. Como dono de site, quero que o guia exija healthcheck, para que o Traefik e eu saibamos quando o app está saudável.
32. Como dono de site, quero que o guia explique como logar a VPS no GHCR com token somente leitura, para baixar imagens privadas com segurança.
33. Como dono de site, quero que o guia descreva o deploy manual (`pull` + `up -d`) e o deploy via CI por SSH como evolução, para ter um caminho claro hoje e amanhã.
34. Como dono do bbcontainer, quero uma lista exata do que mudar no compose dele, para migrá-lo ao novo contrato antes de ir para a VPS.
35. Como dono do conan-torres, quero uma lista exata do que mudar (workflow de build/push no GHCR, remover porta 8080, healthcheck, labels com `le-dns`, manter o volume do SQLite), para migrá-lo ao novo contrato.
36. Como estudante, quero um roteiro para testar o DNS-01 localmente no meu computador com staging e um subdomínio de teste do `conantorres.dev`, para validar o modelo antes da VPS.
37. Como estudante, quero a delegação de DNS-01 por CNAME documentada como estudo extra, para entender a alternativa ao HTTP-01 em domínios sem API.
38. Como mantenedor, quero um smoke test local que sobe a pilha com um app de exemplo e verifica o comportamento por fora, para ter confiança ao mudar a configuração.
39. Como mantenedor, quero um checklist manual de emissão real de certificados (DNS-01 local em staging, HTTP-01 na VPS), para validar o que o smoke test não cobre.
40. Como dono de VPS, quero documentado como acessar o painel por túnel SSH, para inspecionar rotas quando precisar.
41. Como dono de VPS, quero lembrar de habilitar o proxy da Cloudflare (nuvem laranja) depois, para não esquecer esse próximo passo de estudo.

## Implementation Decisions

**Escopo do repositório**
- O repositório contém só a pilha de borda: Traefik v3 (versão exata fixada), `docker-socket-proxy`, configuração estática, configuração dinâmica compartilhada, `.env.example`, README e guia de integração. Não contém compose de sites nem automação de provisionamento (Ansible/scripts) — só um checklist no README.
- Reaproveitamento: clonar o repositório em cada VPS; tudo que é específico do servidor vai no `.env` local, nunca versionado.

**Contrato (nomes oficiais que todo projeto segue)**
- Entradas: `web` (porta 80) e `websecure` (porta 443).
- Rede Docker externa compartilhada: `proxy` (criada uma vez no servidor; Traefik e sites se conectam a ela).
- Emissores de certificado: `le-dns` (DNS-01 via Cloudflare) e `le-http` (HTTP-01).
- Peças compartilhadas expostas via provedor de arquivo, referenciadas pelos sites com sufixo `@file`: cabeçalhos de segurança, compressão, redirecionamento www→raiz. Os nomes exatos das peças são definidos na implementação e documentados no guia.
- O bbcontainer não é referência; ele será ajustado ao contrato.

**Configuração estática**
- Arquivo YAML comentado (não flags no compose).
- `web` redireciona globalmente para `websecure` (redirect permanente) — sites não declaram redirect HTTP→HTTPS.
- Provedor Docker com `exposedByDefault=false`, apontando para o `docker-socket-proxy` (sem montar o socket no Traefik). O proxy de socket libera apenas os endpoints de leitura necessários ao Traefik; fica numa rede interna própria, não na rede `proxy`.
- Provedor de arquivo apontando para a configuração dinâmica compartilhada, com recarga automática.
- Painel/API habilitados, mas não roteados publicamente; acesso via túnel SSH (documentado).
- Métricas Prometheus habilitadas numa entrada interna dedicada, não publicada no host.
- Logs de acesso em JSON; rotação/limite de tamanho via driver de log do Docker.
- Healthcheck do Traefik via ping interno; `restart: unless-stopped`.

**Certificados**
- `le-dns`: desafio DNS-01 com provedor Cloudflare; token de API com permissão `Zone:DNS:Edit` restrita às zonas escolhidas, só no `.env`. Sites em `le-dns` pedem `dominio` + `*.dominio`.
- `le-http`: desafio HTTP-01 na entrada `web`. Sites em `le-http` pedem os nomes exatos (`dominio` e `www.dominio`).
- Uma variável do `.env` define o servidor ACME (staging ou produção) usado pelos dois emissores.
- `acme.json` persistido fora do container, permissão `600`.
- Registros na Cloudflare começam em modo "só DNS" (nuvem cinza).

**Configuração dinâmica compartilhada**
- Cabeçalhos de segurança: HSTS, `frameDeny`/proteção contra iframe, `contentTypeNosniff`, referrer policy.
- Compressão.
- Redirecionamento permanente www→raiz genérico (funciona para qualquer domínio).
- Opções TLS padrão com versão mínima TLS 1.2, aplicadas a todos os routers sem label.

**Guia "como plugar um projeto"** (requisitos para qualquer site)
- Imagem privada no GHCR, construída no CI; nunca build na VPS. VPS faz login no GHCR com token pessoal `read:packages`.
- Sem `ports:`; apenas `expose` e rede externa `proxy`.
- Healthcheck obrigatório.
- Labels: `traefik.enable=true`, rede `proxy`, porta do serviço, router em `websecure` com o emissor adequado e as peças compartilhadas; router de `www` com o redirect compartilhado.
- Arquivos do site na VPS: `/opt/apps/<projeto>` com só `docker-compose.yml` e `.env`.
- Deploy: manual (`docker compose pull && docker compose up -d`) agora; deploy via GitHub Actions por SSH documentado como evolução. Watchtower descartado (arquivado).

**Ajustes nos projetos existentes (antes da VPS)**
- bbcontainer: rede `traefik`→`proxy`; emissor →`le-http`; remover labels próprias de HTTP→HTTPS e de regex www; usar peças compartilhadas; manter healthcheck e imagem GHCR existentes.
- conan-torres: criar workflow de build/push para o GHCR (inspirado no do bbcontainer); compose de produção usando a imagem, sem `ports: 8080`, com `expose`, rede `proxy`, healthcheck, labels com `le-dns`; manter o volume nomeado do SQLite e as variáveis secretas no `.env` da VPS. Avaliar se o conan-torres precisa de um endpoint de health (o bbcontainer usa `/api/health`).

## Testing Decisions

- Um bom teste aqui verifica o comportamento externo do proxy (o que um visitante ou atacante observa via HTTP/TLS), não a estrutura dos arquivos de configuração.
- Ponto de teste acordado:
  - **Smoke test local da pilha**: um script que sobe Traefik + `docker-socket-proxy` + um app de exemplo (`traefik/whoami`) configurado exatamente como o guia manda, e verifica com `curl` (usando resolução de host forçada e aceitando o certificado de teste): HTTP redireciona para HTTPS; `www` redireciona para a raiz; cabeçalhos de segurança e compressão presentes; TLS 1.1 recusado; um container sem `traefik.enable=true` não é roteado; painel e métricas não respondem na porta pública. Derruba a pilha ao final.
- Checklist manual (README), fora do smoke test: emissão DNS-01 local em staging com subdomínio de teste do `conantorres.dev`; emissão HTTP-01 na VPS em staging; virada para produção; conferir certificados curinga vs. nomes exatos.
- Módulo testado: a pilha de borda deste repositório (configuração estática + dinâmica + compose).
- Prior art: não há testes neste repositório (está vazio); os projetos vizinhos não têm testes de infraestrutura.

## Out of Scope

- Proxy da Cloudflare (nuvem laranja), IPs confiáveis/forwarded headers e SSL "Full (strict)" — vira issue no GitHub quando o repositório for publicado.
- Grafana/Prometheus (só as métricas ficam ligadas).
- Delegação DNS-01 por CNAME para domínios sem API — só documentada como estudo.
- Transferir o DNS do `bbcontainermodular.com`.
- Automação de provisionamento da VPS (Ansible, scripts).
- Deploy automatizado dos sites via CI (só documentado como evolução).
- Rate limiting, HTTP/3, autenticação no painel.

## Further Notes

- Repositório será público; nunca versionar `.env`, `acme.json` ou tokens.
- Follow-up após publicar no GitHub: criar a issue "Habilitar proxy da Cloudflare (nuvem laranja)".
- O conan-torres não é puramente uma landing page: tem um leitor com senha e SQLite em volume — por isso imagem privada e preservação do volume.
- Para que serve o token da Cloudflare: o Traefik o usa para criar e remover automaticamente o registro TXT `_acme-challenge` exigido pelo Let's Encrypt em cada emissão/renovação DNS-01.
