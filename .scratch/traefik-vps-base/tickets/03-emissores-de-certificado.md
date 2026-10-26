# 03: Emissores de certificado le-dns / le-http com opção de staging

> **Dificuldade:** Difícil: **modelo sugerido:** Opus (Claude Code) / Opus ou o modelo de raciocínio mais forte disponível (Cursor). Só sugestão, use o modelo que tiver à mão.

**Spec:** ../SPEC.md

**O que construir:** dois emissores ACME:
- `le-dns`: DNS-01 via Cloudflare, com o token no `.env` e permissão `Zone:DNS:Edit` restrita;
- `le-http`: HTTP-01 na entrada `web`.

Uma única variável do `.env` alterna o servidor ACME dos dois entre staging (o ambiente de teste do Let's Encrypt) e produção. O `acme.json` fica persistido fora do container, com permissão `600`. O README ganha:
- o roteiro de teste local de DNS-01 em staging, com um subdomínio de teste do `conantorres.dev` e certificado `dominio` + `*.dominio`;
- o checklist manual de HTTP-01 na VPS e da virada para produção;
- uma explicação de para que serve o token.

**Pontos de teste:**
- Smoke test local da pilha (só regressão: a pilha continua subindo sem token configurado)
- Checklist manual de emissão real (README)

**Bloqueado por:** 01: Pilha mínima de borda com smoke test

Status: ready-for-human

- [x] Com staging ativo, um certificado DNS-01 curinga de teste é emitido localmente para um subdomínio do `conantorres.dev` (verificação manual registrada)
- [x] A troca da variável de staging para produção muda os dois emissores sem outra edição
- [x] Sem token da Cloudflare, a pilha sobe e o smoke test continua passando
- [x] O `acme.json` persiste entre reinícios, com permissão `600`
- [x] O `.env.example` documenta e-mail ACME, token, variável de staging e escopo mínimo do token
- [x] O README documenta a delegação por CNAME como estudo extra

## Verificação manual (2026-10-25)

Roteiro "Testar DNS-01 localmente em staging" do README, com token restrito à zona `conantorres.dev`:

- Emissor `C = US, O = Let's Encrypt, CN = (STAGING) Dastardly Durum YR1`; SAN `DNS:*.teste.conantorres.dev, DNS:teste.conantorres.dev`.
- `acme/le-dns-staging.json` com `-rw-------`.
- Depois de `docker compose up -d --force-recreate traefik`: mesmo serial (`2C49ECE6…E9`), nenhuma nova emissão, nenhum `ERR`.
- Primeira tentativa falhou com `cloudflare: failed to find zone conantorres.dev.: zone could not be found` porque o token estava restrito a outra zona; corrigido o "Zone Resources" do token.
