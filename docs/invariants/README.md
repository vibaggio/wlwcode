# Invariantes executáveis

Este diretório contém invariantes em YAML, não em prosa.

Cada invariante tem:
- `id` — identificador estável
- `pre` — pré-condição
- `post` — pós-condição
- `invariant` — o que **nunca** pode ser violado
- `testes` — lista de testes que devem falhar antes e passar depois

**Regra:** um invariante só é considerado cumprido quando **todos** os testes
da lista passam com sessão `authenticated` real, contra o banco real.

Uma IA que executa um invariante **deve colar a saída real dos testes** no PR.
Se não conseguiu testar, deve dizer explicitamente. Nunca declarar sucesso sem prova.