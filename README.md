# Traefik na VPS

## Painel e métricas via túnel SSH

O painel/API do Traefik (porta 8080) e as métricas Prometheus (porta 8082)
**não** são acessíveis pela internet: nunca respondem em 80/443. O
`docker-compose.yml` publica essas duas portas apenas no loopback da VPS
(`127.0.0.1:8080` e `127.0.0.1:8082`), então só se chega a elas de dentro do
servidor, por um túnel SSH.

No seu computador:

```bash
ssh -N -L 8080:127.0.0.1:8080 -L 8082:127.0.0.1:8082 usuario@IP_DA_VPS
```

Com o túnel aberto, no seu navegador/terminal:

- Painel: <http://localhost:8080/dashboard/> (a barra final é obrigatória)
- API: <http://localhost:8080/api/overview>
- Métricas: <http://localhost:8082/metrics>

Se a porta local já estiver em uso, troque o primeiro número
(ex.: `-L 9090:127.0.0.1:8080`). Feche o túnel com `Ctrl+C`.

Containers na rede `proxy` (ex.: um Prometheus futuro) alcançam as métricas em
`http://traefik:8082/metrics`, sem passar pelo host.

### Logs de acesso

O Traefik grava logs de acesso em JSON na saída padrão do container, com
rotação do Docker (5 arquivos de 10 MB):

```bash
docker compose logs -f traefik
```
