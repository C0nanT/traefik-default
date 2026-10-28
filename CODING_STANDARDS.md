# Padrões de código

Lido na revisão. O que ferramenta checa (teto de tempo dos testes rápidos, no pre-commit) não entra aqui.

## Testes em shell (`testes/`)

- Toda espera tem limite de tentativas e falha com mensagem clara ao esgotar; nunca `until`/`while` aberto.
- Processo em segundo plano que segura um recurso (trava, porta) usa `exec` no último comando, para o `kill` do PID guardado matar quem segura de fato e nada sobreviver ao teste.
