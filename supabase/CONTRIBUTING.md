# CONTRIBUTING — WildLens (WLW)

> **Leia este arquivo inteiro antes de tocar em qualquer linha.**
> Este projeto é **LLM-first** e **server-authoritative**. As regras abaixo não são sugestões.

---

## 0. Arquitetura-alvo (invariante de topo)

```
LLM/client  =  apresentação + solicitação
PostgreSQL  =  autoridade sobre estado, regras, economia e permissões
```

Toda mudança deve respeitar isso. Se você está pensando em mover uma regra
econômica para o JavaScript "porque é mais fácil", **pare**. Está no lugar errado.

---

## 1. As 10 regras de ouro

1. **Se você não consegue provar que a correção funciona rodando um comando,
   você não terminou.**
2. **Toda regra de negócio importante existe no Postgres, não no JSX.**
3. **Toda operação "uma vez por período", "máximo N", "uma recompensa",
   "compra única" ou transferência de ativo é segura contra duas requisições
   simultâneas.** Advisory lock, constraint, ou `FOR UPDATE` — não `if`.
4. **Erro de backend nunca é convertido em sucesso, resposta errada, fim de
   partida, consentimento aceito ou estado persistido no cliente.**
5. **Nenhuma migration aplicada é editada.** Toda mudança nova em migration nova.
6. **Nenhum bundle é editado manualmente.** `app.min.js` é artefato gerado.
7. **Nenhuma chave `service_role` circula no client, no repo ou em logs.**
8. **Nenhuma IA remove RLS para "fazer funcionar".** Se uma view quebra,
   a solução é RPC mínima ou policy. Nunca desabilitar RLS.
9. **Toda ação administrativa sensível é registrada em audit log.**
10. **Todo ativo (carta) destruído, consumido, criado ou transferido tem evento
    em `card_transactions`.** O ledger responde: *"por que essa carta existe?"*

---

## 2. O que NUNCA fazer

Proibido, sem exceção:

- ❌ Mover saldo, moeda ou propriedade de carta para o frontend.
- ❌ Aceitar `p_num_questions` arbitrário em `app_start_quiz`.
- ❌ Confiar em `disabled` de botão para impedir duplicidade.
- ❌ Confiar em `p_time_taken` do cliente para decidir recompensa.
- ❌ Remover RLS para fazer uma view funcionar.
- ❌ Conceder `EXECUTE` a `anon` em RPC de mutação.
- ❌ Colocar `service_role` no browser, no bundle ou em `.env` versionado.
- ❌ Esconder erro de backend transformando-o em `accepted=true`.
- ❌ Tratar `null` de autorização como autorização.
- ❌ Criar segunda implementação paralela do quiz, da economia ou de qualquer regra.
- ❌ Editar `app.min.js` manualmente.
- ❌ Fazer `squash` de migrations de produção sem plano de migração.
- ❌ Refatoração estrutural grande antes de corrigir P0.
- ❌ Apagar policy de RLS sem revisar predicado e impacto.
- ❌ `catch(e){}` vazio em qualquer operação que altere estado.

---

## 3. Fluxo obrigatório para qualquer mudança

```
1. Qual é a regra/invariante do jogo?
2. O banco impede que um cliente malicioso viole essa regra?
3. A operação é atômica sob concorrência?
4. RLS/grants impedem acesso indevido?
5. O frontend representa corretamente loading/error/sucesso?
6. Existe teste automatizado que prova isso?
7. A mudança é reproduzível a partir do repositório?

Se qualquer resposta for "não", PARE e resolva antes de continuar.
```

---

## 4. Como fazer uma mudança no banco

1. **Nunca** edite uma migration já aplicada no remoto.
2. Crie `supabase/migrations/<timestamp>_<descricao>.sql`.
3. Toda função de mutação valida `auth.uid()`.
4. `SECURITY DEFINER` **só** se justificado. Preferir `SECURITY INVOKER`.
   Se `DEFINER`, sempre `search_path = ''` + qualificação de schema.
5. Grants explícitos:
   ```sql
   revoke all on function public.app_xxx(...) from anon, public;
   grant execute on function public.app_xxx(...) to authenticated;
   ```
6. Teste local:
   ```bash
   supabase db reset
   supabase db reset --with-seed
   ```
7. Rode a suíte SQL (ver §6).

---

## 5. Como fazer uma mudança no frontend

1. Fonte é `src/`. **Não** edite `supabase/app.min.js`.
2. Toda chamada Supabase passa por `src/lib/api.js`. Não chame `db.rpc()`
   direto de componentes.
3. Gates (consent, NDA, access, alpha) seguem a máquina de estados:
   ```
   loading → não liberar
   error   → não liberar
   blocked → não liberar
   ready   → liberar somente se autorização explícita = true
   ```
4. `catch` de mutação:
   - não altera estado de jogo;
   - mostra erro;
   - permite retry.
5. Build:
   ```bash
   npm run build
   ```
   O bundle resultante vai para `supabase/app.min.js` via script de build,
   **nunca** copiado à mão.

---

## 6. Como testar

### Local
```bash
supabase start
supabase db reset --with-seed
npm run lint
npm run test
npm run build
```

### Suíte SQL obrigatória
Localizada em `supabase/tests/`. Cobre:

- Quiz: limite 5, resposta imutável, ownership, `p_time_taken` server-side.
- Economia: ledger bate com saldo, cada carta tem 1 owner.
- Concorrência: 2x checkin, 2x claim_mission, 2x claim_achievement,
  2x claim_alpha_welcome, 2x app_start_quiz no limite, 2x showcase,
  2x buy_listing, 2x respond_trade.
- Permissões: `anon` sem mutação; A não lê dados de B; child sem permissão.

### Testes de contrato
Verificam que toda `db.rpc("app_xxx")` no bundle tem função correspondente
no banco, com assinatura compatível, acessível só a `authenticated`.

---

## 7. Ordem de prioridade

```
P0   →  bloqueia qualquer exposição pública
P0.5 →  pré-requisito para testar P0 (baseline, seed, ambiente local)
P1   →  bloqueia aumento de público
P2   →  qualidade, evolução, CI
```

Detalhes em `docs/PROXIMOS_PASSOS.md` e `docs/invariants/P0.yaml`.

**Não inverta a ordem.** Refatoração grande vem depois de P0 e P0.5.

---

## 8. Onde está o quê

```
CONTRIBUTING.md                      ← você está aqui
docs/
  threat_model.md                    ← modelo de ameaça
  PROXIMOS_PASSOS.md                 ← roadmap para humano
  invariants/
    P0.yaml                          ← especificação executável P0
    README.md                        ← como ler o YAML
supabase/
  config.toml                        ← project_id deve bater com o remoto
  migrations/                        ← uma migration por mudança
  seed.sql                           ← dados de catálogo para dev/teste
  tests/                             ← suíte SQL
src/                                 ← source frontend (após P2-A)
.github/workflows/ci.yml             ← CI obrigatório
```

---

## 9. Se você é uma IA

- Leia `CONTRIBUTING.md` **inteiro** antes de qualquer ação.
- Leia `docs/threat_model.md` para entender o modelo de ameaça.
- Leia `docs/invariants/P0.yaml` para saber exatamente o que validar.
- Execute **apenas** o item do roadmap que foi pedido.
- Ao terminar, rode a suíte de testes e **cole a saída real** no PR.
- Se não conseguiu testar, diga explicitamente. **Nunca** declare sucesso sem prova.

> *"A UI nunca é autoridade. O Postgres é a autoridade para propriedade,
> moeda, recompensa, autorização e estado de jogo."*