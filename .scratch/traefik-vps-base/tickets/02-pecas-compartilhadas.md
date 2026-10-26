# 02: Peças compartilhadas (segurança, compressão, www, TLS)

> **Dificuldade:** Médio: **modelo sugerido:** Sonnet (Claude Code) / Sonnet (Cursor). Só sugestão, use o modelo que tiver à mão.

**Spec:** ../SPEC.md

**O que construir:** um arquivo de configuração dinâmica, lido pelo provedor de arquivo com recarga automática, que define as peças reaproveitáveis:
- os cabeçalhos de segurança (HSTS, proteção contra iframe, nosniff, referrer policy);
- a compressão;
- o redirecionamento permanente genérico de `www` para o domínio sem `www`;
- as opções TLS padrão com versão mínima 1.2.

Os sites referenciam as peças com `@file`. O whoami do smoke test passa a usá-las como o guia vai mandar.

**Pontos de teste:**
- Smoke test local da pilha

**Bloqueado por:** 01: Pilha mínima de borda com smoke test

Status: ready-for-human

- [x] O smoke test confirma os cabeçalhos de segurança na resposta do whoami
- [x] O smoke test confirma a compressão quando o cliente envia `Accept-Encoding`
- [x] O smoke test confirma que `www.<host>` redireciona permanentemente para `<host>`, preservando o caminho
- [x] O smoke test confirma que um handshake com TLS 1.1 é recusado e um com TLS 1.2 é aceito
- [x] O TLS mínimo vale sem nenhuma label nos sites
- [x] Os nomes das peças são estáveis e comentados no arquivo
