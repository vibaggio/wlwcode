# WildLens — Plano de Implementação P0/P1/P2

**Base:** auditoria técnica de 06/10/2026 + código recebido + estado remoto Supabase auditado.

## Regra operacional para a outra IA

Não reescrever o jogo. Não mover regras econômicas para o browser. Não “corrigir” removendo RLS/RPCs.

A arquitetura-alvo continua sendo:

> **LLM/client = apresentação + solicitação; PostgreSQL = autoridade sobre estado, regras, economia e permissões.**

Toda mudança deve ser feita como migration versionada + alteração do source + rebuild do bundle + teste.

Nunca editar somente `app.min.js`.

---

# 0. Ordem obrigatória

1. **P0-A — Quiz: limitar quantidade no servidor.**
2. **P0-B — Quiz: impedir reenvio da mesma questão.**
3. **P0-C — Quiz: serializar limite diário.**
4. **P0-D — Frontend: eliminar todos os gates fail-open.**
5. **P0-E — Frontend: distinguir loading/error/ready em perfil e acesso.**
6. Executar testes de abuso P0.
7. **P1-A — Check-in concorrente.**
8. **P1-B — Pacote perfeito diário concorrente.**
9. **P1-C — Username com constraint real.**
10. **P1-D — Showcase com lock.**
11. **P1-E — Views SECURITY DEFINER.**
12. **P1-F — Grants explícitos e superfície RPC.**
13. Executar suíte de concorrência e segurança.
14. **P2-A — Reprodutibilidade/migrations.**
15. **P2-B — Build determinístico.**
16. **P2-C — Testes automatizados/CI.**
17. **P2-D — Divisão do monólito frontend.**
18. Só então considerar aumento de público.

---

# P0 — Correções de segurança e integridade

## P0-A — `app_start_quiz`: servidor deve impor exatamente 5 questões

### Problema

O frontend envia 5, mas o RPC aceita `p_num_questions` arbitrário e repassa para `start_quiz_session()`. A recompensa final é proporcional aos acertos. Portanto, o cliente não pode controlar a quantidade.

### Migration

Criar:

`supabase/migrations/20261006000100_harden_quiz_integrity.sql`

```sql
create or replace function public.app_start_quiz(p_num_questions integer default 5)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_count integer;
    v_limit integer := 5;
    v_today date := (now() at time zone 'America/Sao_Paulo')::date;
begin
    if auth.uid() is null then
        raise exception 'Usuario nao autenticado';
    end if;

    -- A regra do produto é fixa: toda sessão possui exatamente 5 questões.
    if p_num_questions <> 5 then
        raise exception 'Uma sessao de quiz deve conter exatamente 5 questoes';
    end if;

    -- Impede duas abas/requisições simultâneas de ultrapassarem o limite diário.
    perform pg_advisory_xact_lock(
        hashtextextended('quiz_start:' || auth.uid()::text, 0)
    );

    select count(*)
      into v_count
      from quiz_sessions
     where user_id = auth.uid()
       and (started_at at time zone 'America/Sao_Paulo')::date = v_today;

    if v_count >= v_limit then
        raise exception 'Limite de quizzes de hoje atingido. Volte apos a meia-noite.';
    end if;

    return public.start_quiz_session(auth.uid(), 5);
end;
$$;

revoke all on function public.app_start_quiz(integer) from anon, public;
grant execute on function public.app_start_quiz(integer) to authenticated;
```

### Endurecer também o helper interno

O cliente não precisa chamar diretamente `start_quiz_session`.

```sql
revoke all on function public.start_quiz_session(uuid, integer) from anon, authenticated, public;
```

O `app_start_quiz()` continua conseguindo chamá-lo porque é `SECURITY DEFINER` e roda como proprietário.

### Teste obrigatório

```sql
-- Deve falhar:
select public.app_start_quiz(6);
select public.app_start_quiz(100);
select public.app_start_quiz(0);

-- Deve aceitar apenas 5 quando autenticado:
select public.app_start_quiz(5);
```

Não usar testes com `service_role` para validar autorização do usuário. Testar com sessão `authenticated` real.

---

# P0-B — Quiz: uma questão só pode ser respondida uma vez

## Problema

`answer_quiz_question()` atualmente faz `UPDATE` da resposta existente. O frontend recebe `correct_option_id` de `app_answer_quiz()`. Isso permite:

1. responder uma alternativa;
2. receber qual era a correta;
3. enviar a correta novamente;
4. finalizar com a resposta corrigida.

Mesmo que o conhecimento não seja recontado, a recompensa usa o estado final de `quiz_session_answers`.

## Migration

No mesmo migration P0 ou em um segundo migration imediatamente posterior:

```sql
create or replace function public.answer_quiz_question(
    p_session_id uuid,
    p_question_id uuid,
    p_selected_option_id uuid,
    p_time_taken numeric default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_completed timestamptz;
    v_uid uuid;
    v_opt_question uuid;
    v_opt_correct boolean;
    v_limit int;
    v_correct boolean;
    v_prev uuid;
    v_diff text;
    v_delta int := 0;
begin
    select completed_at, user_id
      into v_completed, v_uid
      from quiz_sessions
     where id = p_session_id
     for update;

    if not found or v_uid <> auth.uid() then
        raise exception 'Sessao nao encontrada';
    end if;

    if v_completed is not null then
        raise exception 'Sessao ja finalizada';
    end if;

    select selected_option_id
      into v_prev
      from quiz_session_answers
     where session_id = p_session_id
       and question_id = p_question_id
     for update;

    if not found then
        raise exception 'Esta pergunta nao pertence a sessao';
    end if;

    -- INVARIANTE: uma pergunta respondida nunca muda de resposta.
    if v_prev is not null then
        raise exception 'Esta pergunta ja foi respondida';
    end if;

    select question_id, is_correct
      into v_opt_question, v_opt_correct
      from quiz_answer_options
     where id = p_selected_option_id;

    if not found or v_opt_question <> p_question_id then
        raise exception 'Opcao invalida para esta pergunta';
    end if;

    select time_limit_seconds, difficulty
      into v_limit, v_diff
      from quiz_questions
     where id = p_question_id;

    v_correct := v_opt_correct
                 and (p_time_taken is null or p_time_taken <= v_limit);

    update quiz_session_answers
       set selected_option_id = p_selected_option_id,
           is_correct = v_correct,
           time_taken_seconds = p_time_taken
     where session_id = p_session_id
       and question_id = p_question_id;

    if v_correct then
        v_delta := case v_diff
            when 'facil' then 5
            when 'media' then 10
            when 'dificil' then 20
            when 'extremo' then 35
            else 5
        end;
    else
        v_delta := case v_diff
            when 'dificil' then -10
            when 'extremo' then -20
            else 0
        end;
    end if;

    if v_delta <> 0 then
        update profiles
           set knowledge_rank = greatest(0, coalesce(knowledge_rank, 0) + v_delta)
         where id = v_uid;
    end if;

    return v_correct;
end;
$$;

revoke all on function public.answer_quiz_question(uuid, uuid, uuid, numeric)
    from anon, authenticated, public;
```

O helper deve ficar interno. O cliente chama somente `app_answer_quiz()`.

### `app_answer_quiz()`

Manter o retorno de `correct_option_id` **somente se a UX realmente quiser mostrar a resposta correta após o primeiro envio**. Depois de P0-B isso deixa de ser explorável.

Se o produto não exigir revelar a correta, remover também o campo e simplificar a superfície:

```sql
return jsonb_build_object('correct', v_correct);
```

Minha recomendação para o jogo educativo é **manter a revelação após o primeiro envio**, porque a regra de uma resposta única torna o comportamento seguro e pedagogicamente útil.

---

# P0-C — `app_finish_quiz`: garantir que a sessão pertence ao usuário

O `finish_quiz_session()` faz lock da sessão, mas a camada pública deve ser explicitamente responsável por verificar `auth.uid()`.

A função pública `app_finish_quiz()` deve seguir este padrão:

```sql
if not exists (
    select 1
      from quiz_sessions
     where id = p_session
       and user_id = auth.uid()
       and completed_at is null
) then
    raise exception 'Sessao nao encontrada';
end if;
```

Depois chamar o helper interno.

Também adicionar no `finish_quiz_session()`:

```sql
if v_user <> auth.uid() then
    raise exception 'Sessao nao pertence ao usuario';
end if;
```

Isso torna a autorização uma invariante do helper e da API pública.

---

# P0-D — Frontend: eliminar fail-open jurídico

## Arquivo

`supabase/fauna-fonte_privado.html`

### Estado atual perigoso

```js
useEffect(()=>{
  db.rpc("app_legal_status_v2")
    .then(({data})=>setStatus(data||{accepted:true}))
    .catch(()=>setStatus({accepted:true}));
},[]);
```

### Substituir por

```js
useEffect(() => {
  let alive = true;
  (async () => {
    try {
      const { data, error } = await db.rpc("app_legal_status_v2");
      if (error) throw error;
      if (alive) setStatus(data || { accepted: false, error: "invalid_status" });
    } catch (e) {
      if (alive) {
        setStatus({
          accepted: false,
          error: e?.message || "Não foi possível verificar o consentimento."
        });
      }
    }
  })();
  return () => { alive = false; };
}, []);

if (status === null) return <LoadingGate />;
if (status.error) return <GateError message={status.error} onRetry={...} />;
if (status.accepted) return null;
```

### Regra

**Erro de verificação jurídica = bloquear. Nunca aceitar.**

---

# P0-E — Alpha welcome também deve ser fail-closed

Atual:

```js
.then(({data})=>setStatus(data||{claimed:true}))
.catch(()=>setStatus({claimed:true}));
```

Substituir pela mesma máquina de estados:

```js
null       -> loading
{claimed}  -> estado normal
{error}    -> erro bloqueante/explicado
```

Em erro, não conceder nem presumir que o benefício já foi resgatado. Mostrar:

> “Não foi possível verificar o estado do benefício. Tente novamente.”

---

# P0-F — NDA e carregamento do perfil devem falhar fechados

## Problema atual

```js
if(profile && !profile.nda_accepted_at) {
  return <NDAGate ... />;
}
```

Se a consulta ao perfil falhar, `profile` permanece `null` e a aplicação continua.

## Alteração exata

Criar:

```js
const [profileState, setProfileState] = useState("loading");
// loading | ready | error
```

Em `loadProfile()`:

```js
async function loadProfile() {
  setProfileState("loading");
  try {
    const { data, error } = await db
      .from("profiles")
      .select("username, soft_currency, education_points, lang, nda_accepted_at")
      .eq("id", session.user.id)
      .single();

    if (error) throw error;
    if (!data) throw new Error("Perfil não encontrado");

    setProfile(data);
    setProfileState("ready");

    if (!langInit.current && data.lang) {
      setLang(data.lang);
      langInit.current = true;
    }

    const { data: acct, error: acctError } = await db.rpc("app_account_status");
    if (acctError) throw acctError;
    if (acct) setAcct(acct);
  } catch (e) {
    setProfileState("error");
    setProfile(null);
  }
}
```

No render:

```js
if (profileState === "loading") return <LoadingGate />;
if (profileState === "error") return <GateError ... />;
if (!profile.nda_accepted_at) return <NDAGate ... />;
```

---

# P0-G — `app_my_access`: default deny

## Problema atual

```js
const showMarket = !access || access.show_purchases !== false;
const canBuy = !access || access.allow_purchases !== false;
const showRanked = !access || access.show_ranked !== false;
const canRanked = !access || access.allow_ranked !== false;
```

Se `app_my_access()` falhar, tudo fica liberado.

## Substituir por

```js
const accessReady = access !== null;

const showMarket = accessReady && access.show_purchases === true;
const canBuy = accessReady && access.allow_purchases === true;
const showRanked = accessReady && access.show_ranked === true;
const canRanked = accessReady && access.allow_ranked === true;
```

Se o contrato do RPC usa semântica diferente, normalizar uma vez no loader e manter a regra acima: **ausência de autorização não autoriza**.

Durante `access === null`, mostrar estado “verificando permissões”.

---

# P0-H — `app_accept_terms_v2`: corrigir contrato frontend/backend

A migration final encontrada possui a assinatura correta de três parâmetros:

```sql
app_accept_terms_v2(date, boolean, text)
```

O frontend também envia os três:

```js
p_birth_date
p_parental
p_country
```

A IA deve verificar no banco de destino antes do deploy:

```sql
select pg_get_function_identity_arguments(oid)
from pg_proc
where proname = 'app_accept_terms_v2'
  and pronamespace = 'public'::regnamespace;
```

O resultado esperado é uma assinatura equivalente a:

```text
p_birth_date date, p_parental boolean, p_country text
```

Não manter simultaneamente a antiga assinatura de dois argumentos.

---

# P0 — critérios de aceite

Antes de qualquer P1:

- [ ] `app_start_quiz(6)` falha.
- [ ] Duas chamadas simultâneas não criam mais que 5 sessões no dia permitido.
- [ ] Cada sessão contém exatamente 5 questões.
- [ ] A mesma questão não pode receber duas respostas.
- [ ] Segunda resposta retorna erro.
- [ ] Reenviar a correta após receber `correct_option_id` não é possível.
- [ ] Usuário A não finaliza sessão de usuário B.
- [ ] Erro em `app_legal_status_v2` bloqueia entrada.
- [ ] Erro no carregamento do perfil bloqueia entrada.
- [ ] Erro em `app_my_access` não libera compras/ranqueada.
- [ ] Erro em `app_alpha_status` não cria estado incorreto.

---

# P1 — Concorrência, banco e superfície de segurança

# P1-A — Check-in diário com advisory lock

O RPC atual lê `daily_checkins`, verifica o dia e só depois faz `INSERT ... ON CONFLICT`. Duas requisições simultâneas podem passar pela mesma leitura antes de uma delas atualizar.

Substituir o corpo de `app_checkin()` mantendo o contrato atual e adicionando o lock imediatamente após a autenticação:

```sql
perform pg_advisory_xact_lock(
    hashtextextended('daily_checkin:' || auth.uid()::text, 0)
);
```

Fluxo correto:

```text
auth
  ↓
lock por user
  ↓
select daily_checkins
  ↓
verificar hoje
  ↓
calcular streak/reward
  ↓
upsert daily_checkins
  ↓
atualizar saldo
  ↓
ledger
```

Isso é obrigatório mesmo que o botão do frontend tenha `disabled`, porque duas abas podem chamar o RPC.

---

# P1-B — Pacote perfeito de quiz: serializar concessão

No `finish_quiz_session()`, antes da consulta:

```sql
if v_perfect then
    perform pg_advisory_xact_lock(
        hashtextextended('quiz_perfect_pack:' || v_user::text, 0)
    );
end if;
```

Só depois fazer o `exists` em `pack_openings`.

Isso impede duas sessões perfeitas concorrentes de concederem dois pacotes no mesmo dia.

Não criar índice baseado diretamente em `opened_at AT TIME ZONE 'America/Sao_Paulo'` sem validar a imutabilidade da expressão; o advisory lock é simples e suficiente para o fluxo atual.

---

# P1-C — Username: constraint real no PostgreSQL

O RPC atual faz:

```sql
if exists (
  select 1 from profiles
  where lower(username) = lower(v_clean)
)
```

Isso não é suficiente contra duas requisições concorrentes.

## Migration

Primeiro detectar duplicidades:

```sql
select lower(trim(username)) as normalized, count(*)
from public.profiles
where username is not null
  and trim(username) <> ''
group by lower(trim(username))
having count(*) > 1;
```

Se retornar linhas, corrigir os dados antes de continuar.

Depois:

```sql
create unique index if not exists profiles_username_lower_uidx
on public.profiles (lower(trim(username)))
where username is not null and trim(username) <> '';
```

Alterar `app_set_username()` para tratar `unique_violation`:

```sql
begin
    update profiles
       set username = v_clean
     where id = auth.uid();
exception
    when unique_violation then
        raise exception 'Esse nome ja esta em uso';
end;
```

O teste de `exists` pode permanecer para mensagem rápida, mas a constraint é a autoridade.

---

# P1-D — Showcase: serializar limite de 8

O RPC atual conta as cartas em destaque antes de atualizar. Duas chamadas concorrentes podem observar 7 e ambas colocar a oitava/nona.

Logo após autenticar:

```sql
perform pg_advisory_xact_lock(
    hashtextextended('showcase:' || auth.uid()::text, 0)
);
```

Depois fazer `select count(*)` e `update`.

Não usar lock por `card_id`; o limite é por usuário.

---

# P1-E — Views `SECURITY DEFINER`

As views sinalizadas pelo Security Advisor são:

- `v_education_ranking`
- `v_market_active`
- `v_trade_offers_detail`
- `v_ranked_ranking`
- `v_ranked_history`

## Primeira opção: tornar `security_invoker`

Em PostgreSQL 15+:

```sql
alter view public.v_education_ranking set (security_invoker = true);
alter view public.v_market_active set (security_invoker = true);
alter view public.v_trade_offers_detail set (security_invoker = true);
alter view public.v_ranked_ranking set (security_invoker = true);
alter view public.v_ranked_history set (security_invoker = true);
```

Depois testar todos os consumidores frontend.

O frontend consulta essas views diretamente, portanto o teste deve usar papel `authenticated` real.

## Se alguma view deixar de funcionar

Não voltar automaticamente para `SECURITY DEFINER`.

Primeiro determinar qual tabela/RLS impede a leitura. Se a leitura pública é legítima, criar uma RPC de leitura explicitamente autorizada, com `SECURITY DEFINER` mínimo, `search_path = ''`, grants somente para `authenticated` e sem acesso a dados privados.

---

# P1-F — Auditoria de `SECURITY DEFINER`

O banco possui 94 funções `SECURITY DEFINER` no schema público. Todas estão com `search_path` configurado, o que é positivo.

A próxima regra é reduzir a superfície:

```sql
select
  p.proname,
  pg_get_function_identity_arguments(p.oid),
  p.prosecdef,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.prosecdef
order by p.proname;
```

Para cada helper que não é chamado diretamente pelo frontend:

```sql
revoke all on function public.<funcao>(<assinatura>)
from anon, authenticated, public;
```

Para cada `app_*` usado pelo frontend:

```sql
revoke all on function public.app_xxx(<assinatura>) from anon, public;
grant execute on function public.app_xxx(<assinatura>) to authenticated;
```

Não conceder `EXECUTE` global para `public`.

---

# P1-G — Grants explícitos das views/tabelas

Inventariar:

```sql
select grantee, table_schema, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
order by table_name, grantee, privilege_type;
```

A regra desejada:

- `anon`: sem leitura/escrita de dados privados.
- `authenticated`: somente as leituras necessárias.
- mutações importantes: RPC.
- admin: RPC administrativo com `app_is_admin()`/controle server-side.

Não resolver problemas removendo RLS.

---

# P1-H — Storage `fotos`

Estado atual:

- bucket `fotos` é público;
- não há limite de tamanho;
- não há lista de MIME types.

Se o conteúdo fotográfico precisa ser público, o bucket pode continuar público, mas uploads devem ser fortemente restringidos.

Recomendação:

- aceitar somente `image/jpeg`, `image/png`, `image/webp`;
- limitar tamanho no upload/Storage policy;
- impedir que usuário comum altere foto de outro usuário;
- validar metadados no backend;
- não confiar em extensão de arquivo.

A alteração de Storage deve ser feita pelas APIs/policies do Supabase, não por código React.

---

# P1 — critérios de aceite

- [ ] Duplo clique em check-in concede exatamente uma recompensa.
- [ ] Duas sessões perfeitas simultâneas concedem no máximo um pacote perfeito/dia.
- [ ] Dois usuários não conseguem reservar o mesmo username.
- [ ] Duas abas não conseguem ultrapassar o showcase de 8.
- [ ] Views continuam funcionando com `security_invoker=true` ou foram substituídas por RPCs mínimos.
- [ ] Nenhuma função helper desnecessária possui `EXECUTE` para authenticated.
- [ ] Nenhum RPC de mutação possui `EXECUTE` para anon/public.
- [ ] Storage rejeita MIME/tamanho não permitido.

---

# P2 — Reprodutibilidade, testes e arquitetura

# P2-A — Transformar o banco em source-of-truth reproduzível

O ZIP possui 69 migrations, mas não possui baseline/schema inicial suficiente para reconstruir o banco do zero.

## Objetivo

Um novo ambiente deve poder ser criado a partir do repositório sem depender do banco remoto atual.

Estrutura-alvo:

```text
supabase/
  config.toml
  migrations/
    00000000000000_baseline.sql
    20261006000100_harden_quiz_integrity.sql
    ...
  seed.sql
```

## Procedimento

Não inventar um baseline manualmente.

Gerar dump/schema a partir do banco atual usando Supabase CLI e comparar com o estado das migrations.

Depois:

1. criar projeto de teste vazio;
2. aplicar baseline/migrations;
3. aplicar seed;
4. executar testes;
5. comparar tabelas, funções, views, policies e grants.

O projeto remoto atualmente possui histórico de migrations, portanto não reexecutar baseline destrutivamente sobre ele. Baseline é para reconstrução de ambientes novos ou estratégia de squash planejada.

Também corrigir `config.toml` para que `project_id` represente o projeto oficial ou remover o vínculo local se o repositório deve funcionar contra múltiplos projetos.

---

# P2-B — `seed.sql`

O `config.toml` referencia `seed.sql`, mas o arquivo não está presente no pacote.

Criar um seed mínimo e determinístico contendo somente dados de catálogo necessários para desenvolvimento/testes:

- espécies;
- atributos/faixas;
- raridades/configuração;
- perguntas/opções de teste;
- packs;
- cosméticos;
- conquistas.

Não colocar no seed:

- contas reais;
- tokens;
- URLs privadas;
- dados pessoais;
- saldos reais;
- histórico de produção.

---

# P2-C — Build determinístico

## Criar

```text
package.json
package-lock.json
src/
  main.jsx
  supabase.js
  components/
  features/
    quiz/
    collection/
    market/
    trades/
    ranked/
    family/
    account/
    admin/
  lib/
    api.js
    gates.js
    errors.js
```

O HTML privado atual deixa de ser source-of-truth.

O source-of-truth passa a ser `src/`.

## `package.json` mínimo

```json
{
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "lint": "eslint .",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  }
}
```

Se a equipe quiser continuar em JavaScript puro, manter `.jsx` e configurar ESLint/Vitest sem TypeScript inicialmente. Não introduzir TypeScript e refatoração completa simultaneamente.

---

# P2-D — Centralizar chamadas Supabase

Hoje as chamadas RPC estão espalhadas pelo componente monolítico.

Criar `src/lib/api.js`:

```js
export async function rpc(name, params) {
  const { data, error } = await db.rpc(name, params);
  if (error) throw error;
  return data;
}
```

E wrappers de domínio:

```js
export const quizApi = {
  status: () => rpc("app_quiz_status"),
  start: () => rpc("app_start_quiz", { p_num_questions: 5 }),
  questions: (session) => rpc("app_get_session_questions", { p_session: session }),
  answer: (session, question, option, time) => rpc("app_answer_quiz", {
    p_session: session,
    p_question: question,
    p_option: option,
    p_time: time
  }),
  finish: (session) => rpc("app_finish_quiz", { p_session: session })
};
```

A regra “5 questões” fica explícita no frontend, mas continua obrigatória no banco.

---

# P2-E — Estado de gates centralizado

Criar `src/lib/gates.js`:

```js
export const GateState = Object.freeze({
  LOADING: "loading",
  READY: "ready",
  BLOCKED: "blocked",
  ERROR: "error"
});
```

Todo gate de:

- consentimento;
- NDA;
- acesso;
- compras;
- ranked;
- alpha;

deve seguir a mesma máquina de estados.

Regra única:

```text
loading -> não liberar ação
error   -> não liberar ação
blocked -> não liberar ação
ready   -> liberar somente se autorização explícita = true
```

---

# P2-F — Testes automatizados obrigatórios

Criar testes de banco/integração para:

## Quiz

```text
start com 4 -> rejeita
start com 5 -> aceita
start com 6 -> rejeita
segunda resposta -> rejeita
responder sessão de outro usuário -> rejeita
finalizar sessão de outro usuário -> rejeita
resposta após finish -> rejeita
5 questões -> recompensa máxima = 50
6 questões impossíveis via RPC
```

## Economia

```text
duplo buy pack -> uma cobrança por operação
buy listing concorrente -> somente um comprador vence
trade concorrente -> somente uma conclusão
checkin concorrente -> uma recompensa
perfect quiz concorrente -> um pack/dia
burn de carta listada -> rejeita
```

## Permissões

```text
anon -> nenhum RPC mutador
anon -> nenhum dado privado
authenticated A -> nenhum dado privado de B
child -> não pode alterar controles parentais
não-admin -> nenhum RPC admin efetivo
```

## Frontend

Testar pelo menos:

- erro de `app_legal_status_v2`;
- erro de `app_my_access`;
- erro de `profiles`;
- erro de `app_alpha_status`;
- perda de conexão durante quiz;
- refresh no meio do quiz;
- duas abas do mesmo usuário;
- mobile estreito;
- teclado sem mouse.

---

# P2-G — CI obrigatório

Criar `.github/workflows/ci.yml` com:

```text
checkout
→ npm ci
→ npm run lint
→ npm run test
→ npm run build
```

E, em pipeline separado para banco:

```text
supabase start
→ aplicar migrations
→ aplicar seed
→ testes de integração
```

O CI deve falhar se:

- build falhar;
- testes falharem;
- migration não puder ser aplicada em banco limpo;
- lint encontrar erro configurado como error.

---

# P2-H — Remover o modelo “fonte + bundle manual”

Depois do build funcionar:

1. `fauna-fonte_privado.html` deixa de ser o source-of-truth.
2. `app.min.js` passa a ser artefato gerado.
3. O GitHub armazena `src/` + configuração de build.
4. Deploy usa o bundle gerado.
5. Nenhum humano/IA deve editar diretamente o bundle.

---

# 6. O que NÃO deve ser feito pela outra IA

## Não fazer

- não mover saldo/moeda para React;
- não aceitar `p_num_questions` maior porque “o frontend não envia”; 
- não confiar em `disabled` de botão para impedir duplicidade;
- não remover RLS para fazer uma view funcionar;
- não conceder `anon` para RPCs de mutação;
- não colocar `service_role` no browser;
- não esconder erro de backend transformando-o em `accepted=true`;
- não tratar `null` de autorização como autorização;
- não criar uma segunda implementação paralela do quiz;
- não editar `app.min.js` manualmente;
- não squashar migrations de produção sem plano de migração;
- não fazer refatoração estrutural grande antes de corrigir P0.

---

# 7. Critério para considerar P0 concluído

O WildLens só pode avançar para público maior quando um usuário com conhecimento do código, usando chamadas RPC diretamente, não conseguir:

1. aumentar o número de questões do quiz;
2. responder uma mesma questão duas vezes;
3. alterar a resposta depois de descobrir a correta;
4. exceder o limite diário por concorrência;
5. entrar sem consentimento por erro de rede;
6. entrar sem NDA por erro de leitura de perfil;
7. obter acesso a compras/ranked por falha de `app_my_access`.

---

# 8. Critério para considerar P1 concluído

Além do P0:

- check-in concorrente é idempotente;
- recompensa de quiz perfeito é serializada;
- username possui constraint real;
- showcase respeita limite sob concorrência;
- views privilegiadas foram convertidas para invoker ou substituídas por RPCs mínimos;
- grants estão documentados e testados;
- Storage possui restrições adequadas;
- Security Advisor não possui findings críticos/altos não justificados.

---

# 9. Critério para considerar P2 concluído

O projeto deve conseguir ser reconstruído por uma IA que recebeu somente o repositório:

```text
clone
→ instalar dependências
→ subir Supabase local
→ migrations
→ seed
→ testes
→ build
→ deploy
```

Sem depender de:

- estado oculto de um banco antigo;
- arquivo HTML privado não documentado;
- edição manual do bundle;
- conhecimento oral do desenvolvedor;
- credenciais armazenadas no repositório.

---

# 10. Checklist final da outra IA

## P0

- [ ] Criar migration `20261006000100_harden_quiz_integrity.sql`.
- [ ] Limitar quiz a exatamente 5 no servidor.
- [ ] Adicionar lock diário de quiz.
- [ ] Tornar resposta de questão imutável.
- [ ] Garantir ownership no finish.
- [ ] Corrigir `ConsentGate` para fail-closed.
- [ ] Corrigir `AlphaWelcome` para fail-closed.
- [ ] Corrigir `Main` para profile fail-closed.
- [ ] Corrigir `app_my_access` para default deny.
- [ ] Validar assinatura final de `app_accept_terms_v2`.
- [ ] Testar abuso diretamente contra RPC.

## P1

- [ ] Lock no check-in.
- [ ] Lock no perfect-pack.
- [ ] Unique index de username.
- [ ] Lock do showcase.
- [ ] `security_invoker` nas cinco views, se compatível.
- [ ] Auditoria de EXECUTE em todas as funções.
- [ ] Grants explícitos.
- [ ] Storage restrito.
- [ ] Novo ciclo Security Advisor.

## P2

- [ ] Baseline/reconstrução limpa.
- [ ] `seed.sql`.
- [ ] `package.json` + lockfile.
- [ ] `src/` modular.
- [ ] build determinístico.
- [ ] Vitest/integration tests.
- [ ] GitHub Actions.
- [ ] bundle gerado automaticamente.
- [ ] documentação de deploy.

---

# Decisão arquitetural final

A arquitetura do WildLens deve permanecer **LLM-first e server-authoritative**.

A IA que modificar o sistema deve raciocinar sempre nesta ordem:

```text
1. Qual é a regra/invariante do jogo?
2. O banco impede que um cliente malicioso viole essa regra?
3. A operação é atômica sob concorrência?
4. RLS/grants impedem acesso indevido?
5. O frontend representa corretamente o estado de erro/loading/sucesso?
6. Existe teste automatizado que prove isso?
7. A mudança é reproduzível a partir do repositório?
```

Se uma regra importante só existe em JavaScript, ela está no lugar errado.

Se uma autorização depende de `null` significar “provavelmente liberado”, ela está no lugar errado.

Se uma restrição econômica é apenas um `if` antes de um `update`, ela precisa de uma proteção transacional/constraint/lock no banco.

Esse é o princípio que deve orientar todas as mudanças posteriores.
