-- =============================================================================
-- supabase/tests/quiz_integrity.sql
-- Invariantes: QUIZ-01, QUIZ-02, QUIZ-03, QUIZ-04, QUIZ-06  (docs/invariants/P0.yaml)
--
-- Execucao (qualquer cliente que fale SQL contra o banco com a migration aplicada):
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/quiz_integrity.sql
--
-- Como funciona
--   * TUDO roda numa unica transacao que termina em ROLLBACK: usuarios, perguntas e
--     sessoes de teste nao ficam no banco.
--   * Cada teste imprime "NOTICE: [PASS] <invariante> - <o que foi testado>".
--   * Um teste que falha levanta EXCEPTION "[FAIL] ..." e, com ON_ERROR_STOP, aborta tudo.
--   * Chamadas de cliente usam papel `authenticated`/`anon` reais (SET LOCAL ROLE) e
--     request.jwt.claims, exatamente como o PostgREST faz.
--
-- Fora do alcance de um teste de sessao unica (NAO validado aqui):
--   * "2x app_answer_quiz em paralelo -> exatamente 1 sucesso" (QUIZ-02): exige duas
--     conexoes simultaneas. A garantia vem de SELECT ... FOR UPDATE na sessao e na
--     linha da resposta (inspecionavel no corpo das funcoes).
-- =============================================================================
begin;

create temp table quiz_test_log (n serial primary key, id text, label text);
create temp table ctx (a1 uuid, a2 uuid, a3 uuid, a4 uuid, a5 uuid, a6 uuid);
create temp table st  (k text primary key, v uuid);

-- ---------------------------------------------------------------- helpers ----
-- Asserta uma condicao. Falha => EXCEPTION. NULL conta como falha.
create function pg_temp.t(p_id text, p_label text, p_cond boolean) returns void
language plpgsql as $f$
begin
    if p_cond is not true then
        raise exception '[FAIL] % - %', p_id, p_label;
    end if;
    insert into pg_temp.quiz_test_log (id, label) values (p_id, p_label);
    raise notice '[PASS] % - %', p_id, p_label;
end
$f$;

-- Executa p_sql (1 coluna de texto) como p_role com o usuario p_uid.
-- Retorna o valor, ou 'ERR: <mensagem>' se a chamada falhar.
-- p_role nulo = nao troca de papel (so seta os claims).
create function pg_temp.run_as(p_role text, p_uid uuid, p_sql text) returns text
language plpgsql as $f$
declare v_out text;
begin
    perform set_config('request.jwt.claims',
        case when p_uid is null
             then json_build_object('role', coalesce(p_role, 'authenticated'))::text
             else json_build_object('sub', p_uid, 'role', coalesce(p_role, 'authenticated'))::text end,
        true);
    if p_role is not null then
        execute format('set local role %I', p_role);
    end if;
    execute p_sql into v_out;
    reset role;
    perform set_config('request.jwt.claims', '', true);
    return coalesce(v_out, 'OK');
exception when others then
    perform set_config('request.jwt.claims', '', true);
    return 'ERR: ' || sqlerrm;
end
$f$;

create function pg_temp.mk_user(p_name text) returns uuid
language plpgsql as $f$
declare v uuid := gen_random_uuid();
begin
    insert into auth.users (id, aud, role, email)
    values (v, 'authenticated', 'authenticated', p_name || '_' || v || '@test.invalid');
    insert into public.profiles (id, username)
    values (v, left(p_name || '_' || replace(v::text, '-', ''), 24))
    on conflict (id) do nothing;
    return v;
end
$f$;

create function pg_temp.qs(p_sess uuid) returns uuid[]
language sql as $f$
    select array(select question_id from public.quiz_session_answers
                  where session_id = p_sess order by question_id)
$f$;

create function pg_temp.opt(p_q uuid, p_right boolean) returns uuid
language sql as $f$
    select id from public.quiz_answer_options
     where question_id = p_q and is_correct = p_right limit 1
$f$;

-- Responde via RPC publica app_answer_quiz como p_uid.
create function pg_temp.answer(p_uid uuid, p_sess uuid, p_q uuid, p_right boolean,
                               p_reported numeric default 0) returns text
language plpgsql as $f$
begin
    return pg_temp.run_as('authenticated', p_uid,
        format('select public.app_answer_quiz(%L, %L, %L, %s)::text',
               p_sess, p_q, pg_temp.opt(p_q, p_right), coalesce(p_reported::text, 'null')));
end
$f$;

create function pg_temp.finish(p_uid uuid, p_sess uuid) returns text
language plpgsql as $f$
begin
    return pg_temp.run_as('authenticated', p_uid,
        format('select row_to_json(f)::text from public.app_finish_quiz(%L) f', p_sess));
end
$f$;

-- ------------------------------------------------------------------ setup ----
-- 6 usuarios novos e 5 perguntas deterministicas (limite 15 s); as demais ficam inativas.
insert into ctx
select pg_temp.mk_user('qt1'), pg_temp.mk_user('qt2'), pg_temp.mk_user('qt3'),
       pg_temp.mk_user('qt4'), pg_temp.mk_user('qt5'), pg_temp.mk_user('qt6');

do $setup$
declare qids uuid[] := '{}'; q uuid; i int;
begin
    for i in 1 .. 5 loop
        insert into public.quiz_questions (question_text, difficulty, time_limit_seconds, is_active, source)
        values ('[TESTE] pergunta ' || i, 'facil', 15, true, 'quiz_integrity_test')
        returning id into q;
        insert into public.quiz_answer_options (question_id, option_text, is_correct)
        values (q, 'certa', true), (q, 'errada A', false), (q, 'errada B', false), (q, 'errada C', false);
        qids := qids || q;
    end loop;
    update public.quiz_questions set is_active = false where not (id = any (qids));
    raise notice '[SETUP] 6 usuarios e 5 perguntas de teste criados (rollback no final)';
end
$setup$;

-- ---------------------------------------------------------------- QUIZ-01 ----
-- Sessao de quiz tem exatamente 5 questoes.
do $q01$
declare u uuid; r text; sess uuid; n int; v text; def text;
        bad text[] := array['6', '0', '-1', '100', 'null', '4'];
begin
    select a1 into u from pg_temp.ctx;

    r := pg_temp.run_as('authenticated', u, 'select public.app_start_quiz(5)::text');
    perform pg_temp.t('QUIZ-01', 'app_start_quiz(5) cria sessao e retorna o uuid', r not like 'ERR%');
    sess := r::uuid;
    insert into pg_temp.st values ('s1', sess);

    select count(*) into n from public.quiz_session_answers where session_id = sess;
    perform pg_temp.t('QUIZ-01', 'a sessao tem exatamente 5 linhas em quiz_session_answers', n = 5);
    perform pg_temp.t('QUIZ-01', 'quiz_sessions.total_questions = 5',
        (select total_questions from public.quiz_sessions where id = sess) = 5);

    foreach v in array bad loop
        r := pg_temp.run_as('authenticated', u, format('select public.app_start_quiz(%s)::text', v));
        perform pg_temp.t('QUIZ-01', format('app_start_quiz(%s) e rejeitado com "exatamente 5 questoes"', v),
            r like 'ERR:%exatamente 5 questoes%');
    end loop;

    select count(*) into n from public.quiz_sessions where user_id = u;
    perform pg_temp.t('QUIZ-01', 'chamadas invalidas nao criaram nenhuma sessao (continua 1)', n = 1);

    r := pg_temp.run_as('anon', null, 'select public.app_start_quiz(5)::text');
    perform pg_temp.t('QUIZ-01', 'anon nao tem EXECUTE em app_start_quiz', r like 'ERR:%permission denied%');

    r := pg_temp.run_as('authenticated', u, format('select public.start_quiz_session(%L, 100)::text', u));
    perform pg_temp.t('QUIZ-01', 'authenticated nao chama o helper start_quiz_session(uid, 100)',
        r like 'ERR:%permission denied%');

    def := pg_get_functiondef('public.app_start_quiz(integer)'::regprocedure);
    perform pg_temp.t('QUIZ-01', 'app_start_quiz toma pg_advisory_xact_lock ANTES de contar as sessoes do dia',
        position('pg_advisory_xact_lock' in def) > 0
        and position('pg_advisory_xact_lock' in def) < position('count(*)' in def));
end
$q01$;

-- ---------------------------------------------------------------- QUIZ-02 ----
-- Resposta imutavel apos persistida.
do $q02$
declare u uuid; s uuid; qs uuid[]; q1 uuid; q2 uuid; w uuid; c uuid; r text;
        sel uuid; ic boolean;
begin
    select a1 into u from pg_temp.ctx;
    select v into s from pg_temp.st where k = 's1';
    qs := pg_temp.qs(s); q1 := qs[1]; q2 := qs[2];
    w := pg_temp.opt(q1, false); c := pg_temp.opt(q1, true);

    r := pg_temp.answer(u, s, q1, false);
    perform pg_temp.t('QUIZ-02', '1a resposta (errada) e aceita',
        r not like 'ERR%' and (r::jsonb ->> 'correct') = 'false');
    perform pg_temp.t('QUIZ-02', 'a resposta revela a opcao correta (contrato do jogo)',
        (r::jsonb ->> 'correct_option_id') = c::text);

    r := pg_temp.answer(u, s, q1, true);
    perform pg_temp.t('QUIZ-02', 'reenviar a opcao CORRETA na mesma pergunta -> erro "ja foi respondida"',
        r like 'ERR:%ja foi respondida%');
    select selected_option_id, is_correct into sel, ic
      from public.quiz_session_answers where session_id = s and question_id = q1;
    perform pg_temp.t('QUIZ-02', 'linha inalterada apos a tentativa de reescrita (opcao errada, is_correct=false)',
        sel = w and ic = false);

    r := pg_temp.answer(u, s, q1, false);
    perform pg_temp.t('QUIZ-02', 'reenviar a MESMA opcao tambem e rejeitado', r like 'ERR:%ja foi respondida%');

    r := pg_temp.run_as('authenticated', u, format(
        'with x as (update public.quiz_session_answers set selected_option_id = %L, is_correct = true '
        'where session_id = %L returning 1) select count(*)::text from x', c, s));
    perform pg_temp.t('QUIZ-02', 'UPDATE direto em quiz_session_answers por authenticated e bloqueado (0 linhas ou permission denied)',
        r = '0' or r like 'ERR:%permission denied%');
    select selected_option_id, is_correct into sel, ic
      from public.quiz_session_answers where session_id = s and question_id = q1;
    perform pg_temp.t('QUIZ-02', 'apos o UPDATE direto a resposta continua a original', sel = w and ic = false);

    r := pg_temp.run_as('authenticated', u, format(
        'select public.answer_quiz_question(%L, %L, %L, 0)::text', s, q2, pg_temp.opt(q2, true)));
    perform pg_temp.t('QUIZ-02', 'authenticated nao chama o helper answer_quiz_question direto',
        r like 'ERR:%permission denied%');

    r := pg_temp.run_as('authenticated', u, format(
        'select public.app_answer_quiz(%L, %L, %L, 0)::text', s, gen_random_uuid(), pg_temp.opt(q2, true)));
    perform pg_temp.t('QUIZ-02', 'pergunta que nao pertence a sessao e rejeitada', r like 'ERR:%nao pertence a sessao%');

    r := pg_temp.run_as('authenticated', u, format(
        'select public.app_answer_quiz(%L, %L, %L, 0)::text', s, q2, pg_temp.opt(q1, true)));
    perform pg_temp.t('QUIZ-02', 'opcao de OUTRA pergunta e rejeitada', r like 'ERR:%Opcao invalida%');

    -- A FK de selected_option_id e ON DELETE SET NULL: simula a opcao apagada.
    update public.quiz_session_answers set selected_option_id = null
     where session_id = s and question_id = q1;
    r := pg_temp.answer(u, s, q1, true);
    perform pg_temp.t('QUIZ-02', 'mesmo com selected_option_id nulo (FK SET NULL) a resposta continua imutavel (answered_at)',
        r like 'ERR:%ja foi respondida%');
    update public.quiz_session_answers set selected_option_id = w
     where session_id = s and question_id = q1;
end
$q02$;

-- ---------------------------------------------------------------- QUIZ-06 ----
-- Ownership de sessao: B nao le, nao responde, nao finaliza a sessao de A.
do $q06$
declare a uuid; b uuid; s uuid; qs uuid[]; q2 uuid; r text;
begin
    select a1, a2 into a, b from pg_temp.ctx;
    select v into s from pg_temp.st where k = 's1';
    qs := pg_temp.qs(s); q2 := qs[2];

    r := pg_temp.finish(b, s);
    perform pg_temp.t('QUIZ-06', 'B chama app_finish_quiz(sessao de A) -> "Sessao nao encontrada"',
        r like 'ERR:%Sessao nao encontrada%');
    perform pg_temp.t('QUIZ-06', 'a sessao de A continua aberta apos a tentativa de B',
        (select completed_at is null and reward_granted is not true from public.quiz_sessions where id = s));

    r := pg_temp.answer(b, s, q2, true);
    perform pg_temp.t('QUIZ-06', 'B chama app_answer_quiz(sessao de A) -> "Sessao nao encontrada"',
        r like 'ERR:%Sessao nao encontrada%');
    perform pg_temp.t('QUIZ-06', 'a pergunta de A continua sem resposta apos a tentativa de B',
        (select selected_option_id is null and answered_at is null
           from public.quiz_session_answers where session_id = s and question_id = q2));

    r := pg_temp.run_as('authenticated', b, format(
        'select count(*)::text from public.app_get_session_questions(%L)', s));
    perform pg_temp.t('QUIZ-06', 'B nao le as perguntas da sessao de A', r like 'ERR:%Sessao nao encontrada%');

    r := pg_temp.run_as('authenticated', null, 'select public.app_start_quiz(5)::text');
    perform pg_temp.t('QUIZ-06', 'sem auth.uid(): app_start_quiz -> "Usuario nao autenticado"',
        r like 'ERR:%Usuario nao autenticado%');
    r := pg_temp.run_as('authenticated', null, format('select row_to_json(f)::text from public.app_finish_quiz(%L) f', s));
    perform pg_temp.t('QUIZ-06', 'sem auth.uid(): app_finish_quiz -> "Usuario nao autenticado"',
        r like 'ERR:%Usuario nao autenticado%');
    r := pg_temp.run_as('authenticated', null, format(
        'select public.app_answer_quiz(%L, %L, %L, 0)::text', s, q2, pg_temp.opt(q2, true)));
    perform pg_temp.t('QUIZ-06', 'sem auth.uid(): app_answer_quiz e rejeitado', r like 'ERR:%');

    -- Ownership DENTRO do helper (so alcancavel como postgres; auth.uid() vem dos claims).
    r := pg_temp.run_as(null, b, format('select row_to_json(f)::text from public.finish_quiz_session(%L) f', s));
    perform pg_temp.t('QUIZ-06', 'helper finish_quiz_session com uid de B -> "Sessao nao pertence ao usuario"',
        r like 'ERR:%Sessao nao pertence ao usuario%');
    r := pg_temp.run_as(null, null, format('select row_to_json(f)::text from public.finish_quiz_session(%L) f', s));
    perform pg_temp.t('QUIZ-06', 'helper finish_quiz_session com auth.uid() NULO tambem e rejeitado (null nao autoriza)',
        r like 'ERR:%Sessao nao pertence ao usuario%');
    perform pg_temp.t('QUIZ-06', 'a sessao de A segue aberta e sem recompensa',
        (select completed_at is null and reward_granted is not true from public.quiz_sessions where id = s));
end
$q06$;

-- ---------------------------------------------------------------- QUIZ-03 ----
-- Tempo medido no servidor; p_time_taken do cliente e so telemetria.
do $q03$
declare u uuid; a uuid; qs uuid[]; r text; rw record;
begin
    select a3 into u from pg_temp.ctx;
    r := pg_temp.run_as('authenticated', u, 'select public.app_start_quiz(5)::text');
    a := r::uuid; qs := pg_temp.qs(a);

    -- Sessao "antiga": comecou ha 40 s (limite das perguntas de teste: 15 s).
    update public.quiz_sessions set started_at = clock_timestamp() - interval '40 seconds' where id = a;

    r := pg_temp.answer(u, a, qs[1], true, 0);
    perform pg_temp.t('QUIZ-03', 'Q1 correta mas 40 s depois do inicio, cliente diz p_time_taken=0 -> is_correct=false',
        r not like 'ERR%' and (r::jsonb ->> 'correct') = 'false');
    select * into rw from public.quiz_session_answers where session_id = a and question_id = qs[1];
    perform pg_temp.t('QUIZ-03', 'Q1: time_taken_seconds e o tempo do SERVIDOR (>= 39 s)', rw.time_taken_seconds >= 39);
    perform pg_temp.t('QUIZ-03', 'Q1: o tempo informado pelo cliente (0) fica guardado a parte, como telemetria',
        rw.time_taken_reported_seconds = 0);
    perform pg_temp.t('QUIZ-03', 'Q1: answered_at preenchido pelo servidor', rw.answered_at is not null);

    r := pg_temp.answer(u, a, qs[2], true, 999);
    perform pg_temp.t('QUIZ-03', 'Q2 respondida logo apos Q1, cliente diz p_time_taken=999 -> is_correct=true (cliente nao e autoridade)',
        (r::jsonb ->> 'correct') = 'true');
    select * into rw from public.quiz_session_answers where session_id = a and question_id = qs[2];
    perform pg_temp.t('QUIZ-03', 'Q2: tempo contado desde a resposta anterior (< 5 s), nao desde o inicio da sessao (40 s)',
        rw.time_taken_seconds >= 0 and rw.time_taken_seconds < 5 and rw.time_taken_reported_seconds = 999);

    r := pg_temp.answer(u, a, qs[3], true, -1);
    perform pg_temp.t('QUIZ-03', 'p_time_taken negativo -> "Tempo invalido" e a linha fica intacta',
        r like 'ERR:%Tempo invalido%'
        and (select answered_at is null and selected_option_id is null
               from public.quiz_session_answers where session_id = a and question_id = qs[3]));

    -- Simula 20 s de espera desde a resposta anterior (> 15 s).
    update public.quiz_session_answers set answered_at = answered_at - interval '20 seconds'
     where session_id = a and answered_at is not null;
    r := pg_temp.answer(u, a, qs[3], true, 1);
    perform pg_temp.t('QUIZ-03', 'Q3 respondida 20 s apos a anterior (> limite real), cliente diz p_time_taken=1 -> is_correct=false',
        (r::jsonb ->> 'correct') = 'false');

    r := pg_temp.answer(u, a, qs[4], true, 0);
    perform pg_temp.t('QUIZ-03', 'Q4 rapida e correta com p_time_taken=0 -> is_correct=true (o tempo e medido, nao e bonus)',
        (r::jsonb ->> 'correct') = 'true');
    select * into rw from public.quiz_session_answers where session_id = a and question_id = qs[4];
    perform pg_temp.t('QUIZ-03', 'Q4: time_taken_seconds vem do servidor (< 5 s) e o 0 do cliente e so telemetria',
        rw.time_taken_seconds is not null and rw.time_taken_seconds < 5 and rw.time_taken_reported_seconds = 0);
end
$q03$;

-- ---------------------------------------------------------------- QUIZ-04 ----
-- Recompensa deriva so das respostas persistidas: 10 * acertos, com entrada no ledger.
do $q04$
declare u4 uuid; u5 uuid; u6 uuid; s uuid; qs uuid[]; r text; j jsonb; i int;
        bal0 bigint; bal1 bigint; led0 bigint; led1 bigint; n int; sm bigint;
begin
    select a4, a5, a6 into u4, u5, u6 from pg_temp.ctx;

    -- (a) 5 acertos -> 50 moedas
    select coalesce(soft_currency, 0) into bal0 from public.profiles where id = u4;
    select coalesce(sum(amount), 0) into led0 from public.currency_ledger where user_id = u4;
    r := pg_temp.run_as('authenticated', u4, 'select public.app_start_quiz(5)::text');
    s := r::uuid; qs := pg_temp.qs(s);
    for i in 1 .. 5 loop
        r := pg_temp.answer(u4, s, qs[i], true, 0);
        perform pg_temp.t('QUIZ-04', format('sessao 5/5: pergunta %s respondida corretamente', i),
            (r::jsonb ->> 'correct') = 'true');
    end loop;
    r := pg_temp.finish(u4, s);
    perform pg_temp.t('QUIZ-04', '5 acertos: finish executa sem erro', r not like 'ERR%');
    j := r::jsonb;
    perform pg_temp.t('QUIZ-04', '5 acertos: correct_count=5, score=50, reward_currency=50',
        (j ->> 'correct_count') = '5' and (j ->> 'score') = '50' and (j ->> 'reward_currency') = '50');
    select count(*), coalesce(sum(amount), 0) into n, sm
      from public.currency_ledger
     where user_id = u4 and reason = 'quiz_reward';
    perform pg_temp.t('QUIZ-04', '5 acertos: exatamente 1 entrada quiz_reward de 50 no currency_ledger', n = 1 and sm = 50);
    select coalesce(soft_currency, 0) into bal1 from public.profiles where id = u4;
    select coalesce(sum(amount), 0) into led1 from public.currency_ledger where user_id = u4;
    perform pg_temp.t('QUIZ-04', 'variacao do saldo == variacao do ledger (nenhuma recompensa fora do ledger)',
        (bal1 - bal0) = (led1 - led0) and (bal1 - bal0) >= 50);
    perform pg_temp.t('QUIZ-04', 'recompensa == 10 * acertos persistidos em quiz_session_answers',
        50 = 10 * (select count(*) from public.quiz_session_answers where session_id = s and is_correct));

    r := pg_temp.finish(u4, s);
    perform pg_temp.t('QUIZ-04', 'finish repetido e rejeitado', r like 'ERR:%Sessao nao encontrada%');
    select count(*) into n from public.currency_ledger where user_id = u4 and reason = 'quiz_reward';
    perform pg_temp.t('QUIZ-04', 'finish repetido nao pagou de novo (continua 1 entrada no ledger)', n = 1);
    r := pg_temp.answer(u4, s, qs[1], true);
    perform pg_temp.t('QUIZ-04', 'responder depois de finalizar e rejeitado', r like 'ERR:%ja finalizada%');

    -- (b) 3 acertos + 2 erros -> 30 moedas
    r := pg_temp.run_as('authenticated', u5, 'select public.app_start_quiz(5)::text');
    s := r::uuid; qs := pg_temp.qs(s);
    for i in 1 .. 5 loop
        perform pg_temp.answer(u5, s, qs[i], i <= 3);
    end loop;
    r := pg_temp.finish(u5, s);
    j := r::jsonb;
    perform pg_temp.t('QUIZ-04', '3 acertos: correct_count=3, score=30, reward_currency=30',
        r not like 'ERR%' and (j ->> 'correct_count') = '3' and (j ->> 'score') = '30' and (j ->> 'reward_currency') = '30');
    select count(*), coalesce(sum(amount), 0) into n, sm
      from public.currency_ledger where user_id = u5 and reason = 'quiz_reward';
    perform pg_temp.t('QUIZ-04', '3 acertos: exatamente 1 entrada quiz_reward de 30 no ledger', n = 1 and sm = 30);

    -- (c) finish sem respostas -> 0 moedas (comportamento documentado)
    select coalesce(soft_currency, 0) into bal0 from public.profiles where id = u6;
    r := pg_temp.run_as('authenticated', u6, 'select public.app_start_quiz(5)::text');
    s := r::uuid;
    r := pg_temp.finish(u6, s);
    j := r::jsonb;
    perform pg_temp.t('QUIZ-04', 'finish sem respostas: permitido, correct_count=0, score=0, reward_currency=0',
        r not like 'ERR%' and (j ->> 'correct_count') = '0' and (j ->> 'score') = '0' and (j ->> 'reward_currency') = '0');
    select count(*) into n from public.currency_ledger where user_id = u6 and reason = 'quiz_reward';
    perform pg_temp.t('QUIZ-04', 'finish sem respostas: nenhuma entrada quiz_reward e saldo inalterado',
        n = 0 and (select coalesce(soft_currency, 0) from public.profiles where id = u6) = bal0);
end
$q04$;

-- ------------------------------------------------- contrato das 4 funcoes ----
do $sec$
declare f text;
begin
    foreach f in array array['public.app_start_quiz(integer)',
                             'public.answer_quiz_question(uuid,uuid,uuid,numeric)',
                             'public.finish_quiz_session(uuid)',
                             'public.app_finish_quiz(uuid)'] loop
        perform pg_temp.t('SEC', f || ': anon sem EXECUTE',
            not has_function_privilege('anon', f::regprocedure, 'EXECUTE'));
        perform pg_temp.t('SEC', f || ': SECURITY DEFINER com search_path vazio',
            (select p.prosecdef and 'search_path=""' = any (p.proconfig)
               from pg_proc p where p.oid = f::regprocedure));
    end loop;
    perform pg_temp.t('SEC', 'app_start_quiz e app_finish_quiz: authenticated com EXECUTE',
        has_function_privilege('authenticated', 'public.app_start_quiz(integer)'::regprocedure, 'EXECUTE')
        and has_function_privilege('authenticated', 'public.app_finish_quiz(uuid)'::regprocedure, 'EXECUTE'));
    perform pg_temp.t('SEC', 'helpers answer_quiz_question e finish_quiz_session: authenticated SEM EXECUTE',
        not has_function_privilege('authenticated', 'public.answer_quiz_question(uuid,uuid,uuid,numeric)'::regprocedure, 'EXECUTE')
        and not has_function_privilege('authenticated', 'public.finish_quiz_session(uuid)'::regprocedure, 'EXECUTE'));
end
$sec$;

-- ---------------------------------------------------------------- resumo ----
select n, 'PASS' as status, id, label from pg_temp.quiz_test_log order by n;

rollback;