-- =============================================================================
-- 20261006000100_harden_quiz_integrity.sql
-- WildLens - P0 do quiz (invariantes QUIZ-01, QUIZ-02, QUIZ-03, QUIZ-04, QUIZ-06
-- em docs/invariants/P0.yaml). Servidor e a unica autoridade: o cliente solicita,
-- o Postgres decide.
--
-- BLOCOS
--   [1] Colunas. quiz_session_answers ganha:
--         answered_at                 - instante (servidor) em que a resposta foi gravada.
--         time_taken_reported_seconds - tempo informado pelo cliente. SO TELEMETRIA.
--       A coluna ja existente time_taken_seconds passa a guardar o tempo MEDIDO pelo servidor.
--   [2] app_start_quiz (P0-A):  exige p_num_questions = 5 e serializa o limite diario
--       com advisory lock por usuario ANTES de contar as sessoes do dia.
--   [3] answer_quiz_question (P0-B, P0-B'): resposta imutavel (SELECT ... FOR UPDATE na
--       linha da resposta; segunda tentativa = erro) e tempo medido no servidor.
--       p_time_taken NUNCA entra na decisao de is_correct.
--   [4] finish_quiz_session (P0-C): reforca ownership no helper com IS DISTINCT FROM.
--       Corpo da recompensa INALTERADO (10 por acerto; pacote perfeito 1x/dia).
--   [5] app_finish_quiz (P0-C): exige sessao do usuario E ainda aberta (completed_at is null).
--
-- DESVIOS CONSCIENTES EM RELACAO AO PROMPT (justificados no relatorio):
--   D1  Referencia do tempo (P0-B'): o prompt manda medir "answered_at - quiz_sessions.started_at".
--       Os limites sao POR PERGUNTA (15/20/25 s) e uma sessao de 5 perguntas dura 36 s em
--       mediana. Medido desde o inicio da SESSAO, quem responde rapido perderia os acertos
--       das ultimas perguntas. A referencia usada aqui e: para a 1a pergunta,
--       quiz_sessions.started_at (exatamente como no prompt); para as seguintes, o
--       answered_at da resposta anterior da mesma sessao. Continua 100% server-side.
--   D2  "v_user <> auth.uid()" daria NULL (e passaria) com auth.uid() nulo, o que o
--       CONTRIBUTING proibe ("tratar null de autorizacao como autorizacao").
--       Usa-se IS DISTINCT FROM.
--   D3  A imutabilidade (P0-B) testa selected_option_id E answered_at: a FK de
--       selected_option_id e ON DELETE SET NULL e poderia reabrir uma resposta.
--   D4  As 4 funcoes sao SECURITY DEFINER, entao usam search_path = '' com schema
--       qualificado (CONTRIBUTING 4.4). Assinaturas e grants nao mudam.
--
-- Fora do escopo (NAO tocado): frontend, views, RLS, grants de outras funcoes, P1/P2.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- [1] Colunas
-- -----------------------------------------------------------------------------
alter table public.quiz_session_answers
    add column if not exists answered_at timestamptz;

-- Respostas ja gravadas antes desta migration: marca como respondidas (idempotente).
update public.quiz_session_answers a
   set answered_at = coalesce(s.completed_at, s.started_at)
  from public.quiz_sessions s
 where s.id = a.session_id
   and a.selected_option_id is not null
   and a.answered_at is null;

-- Tempo informado pelo cliente (telemetria). O historico existente era justamente o
-- tempo informado pelo cliente, entao e preservado aqui. So roda quando a coluna e criada.
do $migrate_reported$
begin
    if not exists (
        select 1 from information_schema.columns
         where table_schema = 'public'
           and table_name   = 'quiz_session_answers'
           and column_name  = 'time_taken_reported_seconds'
    ) then
        alter table public.quiz_session_answers
            add column time_taken_reported_seconds numeric;
        update public.quiz_session_answers
           set time_taken_reported_seconds = time_taken_seconds
         where time_taken_seconds is not null;
    end if;
end
$migrate_reported$;


-- -----------------------------------------------------------------------------
-- [2] app_start_quiz  (P0-A / QUIZ-01)
-- -----------------------------------------------------------------------------
create or replace function public.app_start_quiz(p_num_questions integer default 5)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_uid   uuid := auth.uid();
    v_count int;
    v_limit int  := 5;   -- maximo de quizzes por dia, reset a meia-noite (horario de Brasilia)
    v_today date := (now() at time zone 'America/Sao_Paulo')::date;
begin
    if v_uid is null then
        raise exception 'Usuario nao autenticado';
    end if;

    -- O cliente nao decide quantas perguntas valem recompensa.
    if p_num_questions is distinct from 5 then
        raise exception 'Uma sessao de quiz deve conter exatamente 5 questoes';
    end if;

    -- Serializa chamadas simultaneas do mesmo usuario antes de contar.
    perform pg_advisory_xact_lock(
        hashtextextended('quiz_start:' || auth.uid()::text, 0)
    );

    select count(*) into v_count
      from public.quiz_sessions
     where user_id = v_uid
       and (started_at at time zone 'America/Sao_Paulo')::date = v_today;

    if v_count >= v_limit then
        raise exception 'Limite de quizzes de hoje atingido. Volte apos a meia-noite.';
    end if;

    return public.start_quiz_session(v_uid, 5);
end;
$function$;

revoke all on function public.app_start_quiz(integer) from public, anon;
grant execute on function public.app_start_quiz(integer) to authenticated;


-- -----------------------------------------------------------------------------
-- [3] answer_quiz_question  (P0-B, P0-B' / QUIZ-02, QUIZ-03, QUIZ-06)
--     Helper interno: chamado por app_answer_quiz; sem EXECUTE para o cliente.
-- -----------------------------------------------------------------------------
create or replace function public.answer_quiz_question(
    p_session_id            uuid,
    p_question_id           uuid,
    p_selected_option_id    uuid,
    p_time_taken            numeric default null   -- telemetria do cliente; nunca autoridade
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_uid           uuid := auth.uid();
    v_owner         uuid;
    v_completed     timestamptz;
    v_started       timestamptz;
    v_prev_option   uuid;
    v_prev_answered timestamptz;
    v_now           timestamptz := clock_timestamp();   -- relogio real, nao o inicio da transacao
    v_ref           timestamptz;
    v_elapsed       numeric;
    v_opt_question  uuid;
    v_opt_correct   boolean;
    v_limit         int;
    v_diff          text;
    v_correct       boolean;
    v_delta         int := 0;
begin
    if v_uid is null then
        raise exception 'Usuario nao autenticado';
    end if;

    -- Trava a sessao: serializa respostas simultaneas e o finish da mesma sessao.
    select user_id, completed_at, started_at
      into v_owner, v_completed, v_started
      from public.quiz_sessions
     where id = p_session_id
       for update;
    if not found or v_owner is distinct from v_uid then
        raise exception 'Sessao nao encontrada';
    end if;
    if v_completed is not null then
        raise exception 'Sessao ja finalizada';
    end if;

    if p_time_taken is not null and p_time_taken < 0 then
        raise exception 'Tempo invalido';
    end if;

    -- Trava a linha da resposta ANTES de qualquer UPDATE.
    select selected_option_id, answered_at
      into v_prev_option, v_prev_answered
      from public.quiz_session_answers
     where session_id = p_session_id
       and question_id = p_question_id
       for update;
    if not found then
        raise exception 'Esta pergunta nao pertence a sessao';
    end if;

    -- INVARIANTE QUIZ-02: a primeira resposta e a unica que conta.
    if v_prev_option is not null or v_prev_answered is not null then
        raise exception 'Esta pergunta ja foi respondida';
    end if;

    select question_id, is_correct
      into v_opt_question, v_opt_correct
      from public.quiz_answer_options
     where id = p_selected_option_id;
    if not found or v_opt_question is distinct from p_question_id then
        raise exception 'Opcao invalida para esta pergunta';
    end if;

    select time_limit_seconds, difficulty
      into v_limit, v_diff
      from public.quiz_questions
     where id = p_question_id;

    -- INVARIANTE QUIZ-03: tempo medido no servidor (ver D1 no cabecalho).
    -- 1a pergunta: desde quiz_sessions.started_at. Demais: desde a resposta anterior.
    select max(answered_at)
      into v_ref
      from public.quiz_session_answers
     where session_id = p_session_id
       and answered_at is not null;
    v_ref     := coalesce(v_ref, v_started);
    v_elapsed := greatest(0, extract(epoch from (v_now - v_ref)));

    -- p_time_taken NAO participa desta decisao.
    v_correct := coalesce(v_opt_correct, false)
                 and (v_limit is null or v_elapsed <= v_limit);

    -- Unico UPDATE: caso "primeira resposta".
    update public.quiz_session_answers
       set selected_option_id          = p_selected_option_id,
           is_correct                  = v_correct,
           time_taken_seconds          = round(v_elapsed, 3),
           time_taken_reported_seconds = p_time_taken,
           answered_at                 = v_now
     where session_id = p_session_id
       and question_id = p_question_id
       and selected_option_id is null
       and answered_at is null;
    if not found then
        raise exception 'Esta pergunta ja foi respondida';
    end if;

    -- Ranking de conhecimento: so na primeira (e unica) resposta.
    if v_correct then
        v_delta := case v_diff when 'facil' then 5 when 'media' then 10
                               when 'dificil' then 20 when 'extremo' then 35 else 5 end;
    else
        v_delta := case v_diff when 'dificil' then -10 when 'extremo' then -20 else 0 end;
    end if;
    if v_delta <> 0 then
        update public.profiles
           set knowledge_rank = greatest(0, coalesce(knowledge_rank, 0) + v_delta)
         where id = v_uid;
    end if;

    return v_correct;
end;
$function$;

revoke all on function public.answer_quiz_question(uuid, uuid, uuid, numeric)
    from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- [4] finish_quiz_session  (P0-C / QUIZ-04, QUIZ-06)
--     Helper interno: chamado por app_finish_quiz; sem EXECUTE para o cliente.
--     Regra de recompensa INALTERADA em relacao a 20260618020031 / 20260617202123.
-- -----------------------------------------------------------------------------
create or replace function public.finish_quiz_session(p_session_id uuid)
returns table(
    correct_count           integer,
    total_questions         integer,
    score                   integer,
    education_points_gained integer,
    reward_currency         bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_user        uuid;
    v_completed   timestamptz;
    v_granted     boolean;
    v_total       int;
    v_correct     int;
    v_score       int;
    v_perfect     boolean;
    v_pack        record;
    i             int;
    v_per_correct constant int := 10;   -- moedas e pontos por acerto (padrao fixo e previsivel)
begin
    select qs.user_id, qs.completed_at, qs.reward_granted, qs.total_questions
      into v_user, v_completed, v_granted, v_total
      from public.quiz_sessions qs
     where qs.id = p_session_id
       for update;

    if not found then
        raise exception 'Sessao nao encontrada';
    end if;

    -- Ownership tambem no helper. IS DISTINCT FROM: auth.uid() nulo NAO autoriza (ver D2).
    if v_user is distinct from auth.uid() then
        raise exception 'Sessao nao pertence ao usuario';
    end if;

    if v_completed is not null or v_granted then
        raise exception 'Sessao ja finalizada';
    end if;

    -- Conta apenas o numero de acertos persistidos.
    select count(*) filter (where sa.is_correct)
      into v_correct
      from public.quiz_session_answers sa
     where sa.session_id = p_session_id;

    v_score   := coalesce(v_correct, 0) * v_per_correct;
    v_perfect := (v_total > 0 and v_correct = v_total);

    update public.quiz_sessions
       set completed_at   = now(),
           correct_count  = v_correct,
           score          = v_score,
           reward_granted = true
     where id = p_session_id;

    update public.profiles
       set education_points = education_points + v_score,
           soft_currency    = soft_currency + v_score
     where id = v_user;

    if v_score > 0 then
        insert into public.currency_ledger (user_id, amount, reason)
        values (v_user, v_score, 'quiz_reward');
    end if;

    -- Pacote por quiz perfeito: no maximo um por dia
    if v_perfect and not exists (
        select 1 from public.pack_openings po
         where po.user_id = v_user and po.source = 'quiz_reward'
           and (po.opened_at at time zone 'America/Sao_Paulo')::date
               = (now() at time zone 'America/Sao_Paulo')::date
    ) then
        select * into v_pack from public.packs where name = 'Pacote Basico' limit 1;
        if found then
            for i in 1 .. v_pack.card_count loop
                perform public.generate_card(v_user, v_pack.set_id, null);
            end loop;
            insert into public.pack_openings (user_id, pack_id, source)
            values (v_user, v_pack.id, 'quiz_reward');
        end if;
    end if;

    perform public.evaluate_achievements(v_user);

    correct_count           := v_correct;
    total_questions         := v_total;
    score                   := v_score;
    education_points_gained := v_score;
    reward_currency         := v_score;
    return next;
end;
$function$;

revoke all on function public.finish_quiz_session(uuid) from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- [5] app_finish_quiz  (P0-C / QUIZ-06)
-- -----------------------------------------------------------------------------
create or replace function public.app_finish_quiz(p_session uuid)
returns table(
    correct_count           integer,
    total_questions         integer,
    score                   integer,
    education_points_gained integer,
    reward_currency         bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
    if auth.uid() is null then
        raise exception 'Usuario nao autenticado';
    end if;

    if not exists (
        select 1 from public.quiz_sessions
         where id = p_session
           and user_id = auth.uid()
           and completed_at is null
    ) then
        raise exception 'Sessao nao encontrada';
    end if;

    return query select * from public.finish_quiz_session(p_session);
end;
$function$;

revoke all on function public.app_finish_quiz(uuid) from public, anon;
grant execute on function public.app_finish_quiz(uuid) to authenticated;