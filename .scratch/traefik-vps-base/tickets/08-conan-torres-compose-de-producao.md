# 08: conan-torres, compose de produção plugado

> **Dificuldade:** Médio: **modelo sugerido:** Sonnet (Claude Code) / Sonnet (Cursor). Só sugestão, use o modelo que tiver à mão.

**Spec:** ../SPEC.md

**O que construir:** um compose de produção do conan-torres que:
- usa a imagem do GHCR;
- não publica a porta `8080` (só `expose`);
- entra na rede `proxy`;
- tem healthcheck;
- usa labels com `le-dns` (`conantorres.dev` + `www`) e as peças compartilhadas;
- mantém o volume nomeado do SQLite.

O fluxo de desenvolvimento local continua funcionando, seja com um compose separado ou com outra abordagem documentada.

**Pontos de teste:**
- Nenhum automatizado; verificar localmente contra a pilha deste repositório

**Bloqueado por:** 05: README e guia "como plugar um projeto"; 06: conan-torres, imagem no GHCR e healthcheck

Status: ready-for-human

- [x] Sem `ports:` no compose de produção
- [x] Atrás da pilha local, o site responde em HTTPS com os cabeçalhos de segurança, e `www` redireciona para o domínio sem `www`
- [x] Os dados do leitor (SQLite) sobrevivem a um `down`/`up` e a uma troca de imagem
- [x] Os segredos vêm do `.env` em `/opt/apps/conan-torres`

## Verificação manual (2026-10-26)

Na VPS (não só localmente), em staging e depois em produção: HTTPS com certificado válido do Let's Encrypt, `curl` sem `-k` verificando a cadeia; HSTS, `nosniff`, `X-Frame-Options: DENY` e `Referrer-Policy` presentes; gzip com `Accept-Encoding`; `www` → domínio sem `www` com 301 preservando caminho e query; container `healthy`.
