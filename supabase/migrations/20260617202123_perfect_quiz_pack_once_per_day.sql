CREATE OR REPLACE FUNCTION public.finish_quiz_session(p_session_id uuid)
 RETURNS TABLE(correct_count integer, total_questions integer, score integer, education_points_gained integer, reward_currency bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_user      uuid;
    v_completed timestamptz;
    v_granted   boolean;
    v_total     int;
    v_correct   int;
    v_score     int;
    v_perfect   boolean;
    v_pack      record;
    i           int;
begin
    -- Colunas qualificadas com qs. para evitar conflito com as saidas da funcao
    select qs.user_id, qs.completed_at, qs.reward_granted, qs.total_questions
      into v_user, v_completed, v_granted, v_total
    from quiz_sessions qs
    where qs.id = p_session_id
    for update;

    if not found then
        raise exception 'Sessao nao encontrada';
    end if;
    if v_completed is not null or v_granted then
        raise exception 'Sessao ja finalizada';
    end if;

    select
        count(*) filter (where sa.is_correct),
        coalesce(sum(case when sa.is_correct then
            case q.difficulty when 'dificil' then 20 when 'media' then 15 else 10 end
            else 0 end), 0)
      into v_correct, v_score
    from quiz_session_answers sa
    join quiz_questions q on q.id = sa.question_id
    where sa.session_id = p_session_id;

    v_perfect := (v_total > 0 and v_correct = v_total);

    update quiz_sessions
       set completed_at   = now(),
           correct_count  = v_correct,
           score          = v_score,
           reward_granted = true
    where id = p_session_id;

    update profiles
       set education_points = education_points + v_score,
           soft_currency    = soft_currency + v_score
    where id = v_user;

    if v_score > 0 then
        insert into currency_ledger (user_id, amount, reason)
        values (v_user, v_score, 'quiz_reward');
    end if;

    -- Pacote por quiz perfeito: no maximo um por dia
    if v_perfect and not exists (
        select 1 from pack_openings po
        where po.user_id = v_user and po.source = 'quiz_reward'
          and (po.opened_at at time zone 'America/Sao_Paulo')::date
              = (now() at time zone 'America/Sao_Paulo')::date
    ) then
        select * into v_pack from packs where name = 'Pacote Basico' limit 1;
        if found then
            for i in 1 .. v_pack.card_count loop
                perform generate_card(v_user, v_pack.set_id, null);
            end loop;
            insert into pack_openings (user_id, pack_id, source)
            values (v_user, v_pack.id, 'quiz_reward');
        end if;
    end if;

    perform evaluate_achievements(v_user);

    correct_count           := v_correct;
    total_questions         := v_total;
    score                   := v_score;
    education_points_gained := v_score;
    reward_currency         := v_score;
    return next;
end;
$function$;;
