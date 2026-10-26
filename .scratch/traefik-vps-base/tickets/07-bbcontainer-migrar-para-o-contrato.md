# 07: bbcontainer, migrar para o contrato

> **Dificuldade:** Médio: **modelo sugerido:** Sonnet (Claude Code) / Sonnet (Cursor). Só sugestão, use o modelo que tiver à mão.

**Spec:** ../SPEC.md

**O que construir:** o compose de produção do bbcontainer segue o guia de integração:
- rede `proxy`;
- emissor `le-http` (o DNS fica na Squarespace);
- as peças compartilhadas de segurança, compressão e `www`.

As labels próprias de HTTP para HTTPS e o regex de `www` são removidos. A imagem do GHCR e o healthcheck existentes ficam como estão.

**Pontos de teste:**
- Nenhum automatizado; verificar localmente contra a pilha deste repositório (staging e certificado padrão)

**Bloqueado por:** 05: README e guia "como plugar um projeto"

Status: ready-for-human

- [x] Nenhuma label de redirecionamento HTTP para HTTPS ou de regex `www` sobra no bbcontainer
- [x] Atrás da pilha local, o site responde em HTTPS com os cabeçalhos de segurança, e `www` redireciona para o domínio sem `www`
- [x] O router usa `le-http` e a rede `proxy`
- [x] As variáveis de ambiente obsoletas (`TRAEFIK_NETWORK`, nomes antigos de entrada e de emissor) foram removidas ou atualizadas

## Verificação manual (2026-10-26)

Na VPS (não só localmente), em staging e depois em produção: HTTPS com certificado válido do Let's Encrypt, `curl` sem `-k` verificando a cadeia; HSTS, `nosniff`, `X-Frame-Options: DENY` e `Referrer-Policy` presentes; gzip com `Accept-Encoding`; `www` → domínio sem `www` com 301 preservando caminho e query; container `healthy`.
