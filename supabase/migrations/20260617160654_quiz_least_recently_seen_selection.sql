create or replace function public.start_quiz_session(p_user_id uuid, p_num_questions integer default 5)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    v_session uuid;
    v_count   int;
begin
    insert into quiz_sessions (user_id, total_questions)
    values (p_user_id, 0)
    returning id into v_session;

    -- Sorteia perguntas ativas priorizando as que este jogador viu menos vezes
    -- e há mais tempo. Desempate aleatorio. Assim o jogador passa por todas
    -- as perguntas antes de qualquer repeticao.
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
    order by coalesce(h.times_seen, 0) asc, h.last_seen asc nulls first, random()
    limit p_num_questions;

    get diagnostics v_count = row_count;

    if v_count = 0 then
        raise exception 'Nao ha perguntas ativas disponiveis';
    end if;

    update quiz_sessions set total_questions = v_count where id = v_session;
    return v_session;
end;
$function$;;
