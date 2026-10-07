CREATE OR REPLACE FUNCTION public.start_quiz_session(p_user_id uuid, p_num_questions integer DEFAULT 5)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_session uuid;
    v_count   int;
    v_rank    int;
    v_allowed text[];
begin
    select coalesce(knowledge_rank,0) into v_rank from profiles where id = p_user_id;
    v_allowed := knowledge_allowed_difficulties(coalesce(v_rank,0));

    insert into quiz_sessions (user_id, total_questions)
    values (p_user_id, 0)
    returning id into v_session;

    -- Sorteia perguntas ativas. Prioriza as dificuldades liberadas pela faixa do
    -- jogador; se nao houver o bastante, completa com as demais. Dentro disso,
    -- prioriza as que o jogador viu menos vezes e ha mais tempo, com desempate aleatorio.
    insert into quiz_session_answers (session_id, question_id)
    select v_session, q.id
    from quiz_questions q
    left join lateral (
        select count(*) as times_seen, max(s.started_at) as last_seen
        from quiz_session_answers a
        join quiz_sessions s on s.id = a.session_id
        where a.question_id = q.id and s.user_id = p_user_id
    ) h on true
    where q.is_active
    order by (case when q.difficulty = any(v_allowed) then 0 else 1 end) asc,
             coalesce(h.times_seen, 0) asc, h.last_seen asc nulls first, random()
    limit p_num_questions;

    get diagnostics v_count = row_count;

    if v_count = 0 then
        raise exception 'Nao ha perguntas ativas disponiveis';
    end if;

    update quiz_sessions set total_questions = v_count where id = v_session;
    return v_session;
end;
$function$;;
