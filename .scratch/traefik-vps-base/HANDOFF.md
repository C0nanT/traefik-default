# Handoff: modelo base de Traefik para VPS

Este arquivo fica em `.scratch/` (versionado junto com SPEC e tickets).

## Onde parou

Última atualização: 2026-10-27. **Projeto em produção e migração fechada. Os 8 tickets estão `ready-for-human`, sem caixas abertas.**

- `bbcontainermodular.com`: **no ar** pela VPS (DNS na Squarespace, já apontava para ela).
- `conantorres.dev`: **no ar** pela VPS (DNS na Cloudflare trocado em 2026-10-26; `www` é CNAME para a raiz). **Nuvem laranja ligada em 2026-10-27**, SSL Full (strict), IP real do visitante nos logs (issue #1 fechada).
- Monitoramento (node exporter, usuário `metricas`, pilha no PC): **no ar desde 2026-10-27**, com alertas no Telegram (veja "O que falta", item 2, concluído).

| Repositório | `main` | GitHub |
|---|---|---|
| `traefik-default` | publicado | <https://github.com/C0nanT/traefik-default> (público) |
| `bbcontainer` | `bd73acf` | imagem privada `ghcr.io/c0nant/bbcontainer` |
| `conan-torres` | `fb2cef6` | imagem privada `ghcr.io/c0nant/conan-torres` (`latest` + SHA) |

## Concluído (sessão de 2026-10-25/26)

1. **Revisão das 3 branches** (`/review-axes`, padrões + SPEC) e merge na `main`. Correções feitas na revisão:
   - `traefik-default`: `grep -F` no teste de log, checagem do ID do Traefik no smoke, aviso do `ufw` sem repetição no README, SPEC atualizada (métricas em `127.0.0.1`).
   - `conan-torres`: `.dockerignore` exclui `docker-compose.prod.yml`; AGENTS.md cobre o compose de produção (`APP_ENV` padrão `production`, regra do `BOOK_FILE_*`).
2. **`traefik-default` publicado** no GitHub (público), com `.scratch/` versionado. Issue #1 (nuvem laranja) aberta.
3. **Imagens no GHCR:** push na `main` dos dois sites; CI e "Build & Push Image" verdes. O pacote do conan-torres nasceu **público** (herdou o repo) e foi trocado para **privado** à mão; conferido com acesso anônimo recusado.
4. **DNS-01 local em staging** com curinga `teste.conantorres.dev` (ticket 03). Primeira tentativa falhou porque o token estava na zona errada.
5. **VPS reconstruída na Hetzner** (Ubuntu 24.04.4, 2 vCPU, 3,7 GB) e montada só pelo README:
   - Docker 29.9.2 / Compose v5.6.1, `ufw` com 22/80/443, rede `proxy`, `/opt/traefik` (git clone) e `/opt/apps/<projeto>`.
   - Login no GHCR com PAT `read:packages` (em `/root/.docker/config.json`).
   - Subida em staging, conferida de fora, e virada para `producao`. Certificados válidos até 24/01/2027 (renovação automática).
6. **DNS do conantorres.dev** trocado da Vercel para a VPS e conferido (HTTPS, `www`, cabeçalhos, health).

7. **Migração fechada:** domínios removidos da Vercel; token da Cloudflare conferido de dentro da VPS (verify `active`, leitura da zona e do DNS ok, sem bloqueio de IP).
8. **Atualização automática** por cron versionada em `vps/` e documentada (README, guia, SPEC).

## O que falta

**Atenção (data marcada):**
1. **Token da Cloudflare expira em 26/10/2027.** Depois disso a renovação do curinga `conantorres.dev` (DNS-01) falha. Tire a expiração no painel da Cloudflare ou gere um token novo antes, troque em `/opt/traefik/.env` e rode `docker compose up -d` em `/opt/traefik`. O alerta de validade do certificado (item 2) pega isso se for esquecido, com o PC ligado, e avisa no Telegram.

**Concluído:**
2. **Prometheus + Grafana: concluído em 2026-10-27, com alertas no Telegram.** O monitoramento ficou no repositório [`homelab-monitoring`](../../../homelab-monitoring), rodando no meu PC (não na VPS). Do lado deste repositório:
   - **node exporter** (`prom/node-exporter`) na pilha de borda, com a rede do host e escutando só em `127.0.0.1:9100`; nenhum container vizinho o alcança (smoke: `testes/verificacoes/06-node-exporter.sh`).
   - **Usuário `metricas`** criado na VPS conforme o README ("Monitoramento a partir de outra máquina"): sem shell, senha travada, chave restrita a abrir túnel para `127.0.0.1:8082` e `127.0.0.1:9100`. Conferido em 2026-10-27: shell recusado, 8080 "administratively prohibited".

   **No ar desde 2026-10-27:** node exporter na VPS, pilha no PC coletando pelo túnel real (jobs `sites`, `traefik` e `node` `up`), reconexão conferida (sessão derrubada na VPS, `docker compose restart traefik` e suspensão real do PC por uma noite: coleta de volta em ~1,5 min, sem alerta falso). Sem monitor externo (UptimeRobot descartado: a pilha é 100% local, e com o PC desligado ninguém vigia os sites).

   **Telegram:** bot criado, `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID` só no `.env` do PC; alerta de teste conferido no celular em 2026-10-27, com o texto de `grafana/provisioning/alerting/mensagem.yml` (gravidade, alerta, alvo e horário de Brasília).

**Concluído (2026-10-27):**
- **Logs no Grafana (Loki e Alloy na borda).** Spec em `homelab-monitoring/.scratch/logs-no-grafana/SPEC.md`. Neste repositório: Loki (`127.0.0.1:3100`, 30 dias, fora da rede `proxy`) e Alloy (lê o Docker só pelo `socket-proxy`, descarta o ruído do próprio proxy) no `docker-compose.yml`, smoke em `testes/verificacoes/07-logs.sh`, README em "Logs (Loki e Alloy)". **Primeiro armazenamento de monitoramento na VPS** (exceção registrada na SPEC). No ar desde 2026-10-27: `permitopen="127.0.0.1:3100"` no `authorized_keys` do `metricas` (8080 segue recusada), Loki ~80 MiB e Alloy ~70 MiB de RAM, linhas de acesso dos 4 routers e da aplicação no painel Logs do Grafana, e o log continua chegando depois de recriar o container (`bbcontainer`, `--force-recreate`).

**Melhorias (quando quiser):**
3. Firewall: aceitar 80/443 no `ufw` só das faixas da Cloudflare (opcional; o `bbcontainermodular.com` não passa pela Cloudflare, então exige regras por destino). A nuvem laranja em si está concluída (issue #1, 2026-10-27).
4. Deploy pelo CI via SSH (hoje o cron cobre, com atraso de até 10 min e erro só no log da VPS).
5. Token da Cloudflare por arquivo (`CF_DNS_API_TOKEN_FILE`) em vez de variável de ambiente.
6. Backup do volume `conan-torres_leitor-data` (SQLite do leitor) e de `/opt/traefik/acme/`.
7. Limpeza de código apontada na revisão (não bloqueante):
   - `traefik-default`: duplicação dos helpers de teste (`afirmar_*`), `healthcheck` no exemplo do whoami, âncoras YAML nos emissores.
   - `bbcontainer`: contrato do Traefik descrito em 4 lugares (compose, README, MAIN.md, guia).
   - `conan-torres`: blocos repetidos entre `docker-compose.yml` e `docker-compose.prod.yml`.

## Operação na VPS

Acesso: `ssh root@<IP da VPS>` (chave já configurada neste computador).

**Atualização automática:** cron a cada 10 min (`/etc/cron.d/atualizar-apps`) roda `/usr/local/bin/atualizar-apps.sh` (fontes em `vps/`, instalação no README), que faz `docker compose pull && up -d` em cada `/opt/apps/*/` e `docker image prune -f`. Log só de mudanças e erros em `/var/log/atualizar-apps.log` (logrotate semanal). Ou seja: push na `main` → no ar em até ~10 min depois do CI.

```bash
# Atualizar um site na hora, sem esperar o cron
cd /opt/apps/<projeto> && docker compose pull && docker compose up -d && docker compose ps

# Estado geral
docker ps --format '{{.Names}}: {{.Status}}'
cd /opt/traefik && docker compose logs --tail 50 traefik

# Painel e métricas (no seu computador; depois abra http://localhost:8080/dashboard/)
ssh -N -L 8080:127.0.0.1:8080 -L 8082:127.0.0.1:8082 -L 9100:127.0.0.1:9100 root@<IP da VPS>
```

- `.env` na VPS (todos `600`, nunca no git): `/opt/traefik/.env` (token CF, e-mail, `ACME_AMBIENTE=producao`), `/opt/apps/bbcontainer/.env`, `/opt/apps/conan-torres/.env` (senha do leitor, ID do livro, `APP_ENV=production`).
- O compose de produção do conan-torres fica na VPS como `/opt/apps/conan-torres/docker-compose.yml` (cópia do `docker-compose.prod.yml`). Se mudar no repo, copie de novo.
- O `.env` local do `traefik-default` (neste computador) tem o token real e `ACME_AMBIENTE=staging`, para testes locais.

## Decisões tomadas (resumo; detalhes na SPEC)

- Este repositório tem **só a pilha de borda**: Traefik `v3.7.16` mais o `docker-socket-proxy`, que dá ao Traefik acesso só de leitura ao Docker. Cada site fica no próprio repositório e se pluga seguindo `docs/como-plugar-um-projeto.md`.
- **Nomes do padrão:** entradas `web` (80) e `websecure` (443), rede `proxy`, emissores `le-dns` e `le-http`, peças `seguranca@file`, `compressao@file` e `www-para-raiz@file`.
- **Certificados no modelo híbrido:**
  - `conantorres.dev` usa DNS-01 pela Cloudflare, com curinga.
  - `bbcontainermodular.com` usa HTTP-01, porque o DNS fica na Squarespace, que não tem API. Esse DNS não vai ser transferido.
- **Teste ou produção:** `ACME_AMBIENTE=staging|producao` no `.env` alterna os dois emissores. O `traefik/iniciar.sh` monta o `traefik.yml` na inicialização, porque o Traefik não lê variáveis dentro do YAML.
- **Painel e métricas:** ficam só em `127.0.0.1`, portas 8080 e 8082 (Traefik) e 9100 (node exporter), e você acessa por túnel SSH. O monitoramento remoto usa o usuário `metricas`, que só abre túnel para 8082 e 9100. O painel responde só pela rede `painel`; os containers dos sites recebem 403.
- **Token da Cloudflare:** precisa de `Zone:Zone:Read` e `Zone:DNS:Edit`, limitadas às zonas escolhidas.
- **Imagens dos sites:** privadas no GHCR, construídas no CI, nunca na VPS. O deploy é `docker compose pull && up -d`, rodado pelo cron a cada 10 min (ou à mão), e o deploy pelo CI via SSH fica como evolução.

## Como verificar que está tudo certo

- No `traefik-default`, rodar `bash testes/smoke.sh`. Ele usa as portas 80, 443, 8080, 8082, 9100 e 3100 do seu computador, então elas precisam estar livres. O resultado esperado é `0 falha(s)`.
- `bash testes/docs.sh` confere a documentação.

## Riscos aceitos e pontos de atenção

- **Containers vizinhos:** um container na rede `proxy` consegue chamar outro site direto, sem passar pelo Traefik, e forjar o `X-Forwarded-For`. O risco é aceito porque só seus próprios containers estão nessa rede. Está documentado no AGENTS.md do conan-torres.
- **Token visível:** o token da Cloudflare entra como variável de ambiente, então quem tem acesso ao Docker consegue vê-lo com `docker inspect`. Uma melhoria futura é passar por arquivo (`CF_DNS_API_TOKEN_FILE`).
- **Docker e firewall:** portas publicadas com `ports:` passam por fora do `ufw`. Por isso o guia proíbe `ports:` nos sites.
- **Teste de TLS 1.1:** o smoke test precisa de um `openssl` que ainda aceite `-tls1_1`.

## Arquivos úteis

- Especificação: `.scratch/traefik-vps-base/SPEC.md`
- Tickets: `.scratch/traefik-vps-base/tickets/`
- Anotações técnicas dos subagentes (versões, labels, decisões de cada ticket): `~/projects/.traefik-notes/`
- Guia para plugar sites: `docs/como-plugar-um-projeto.md`
