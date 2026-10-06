create or replace function public.app_start_quiz(p_num_questions integer default 5)
 returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare
    v_count int;
    v_limit int := 5;   -- maximo de quizzes por dia, reset a meia-noite (horario de Brasilia)
    v_today date := (now() at time zone 'America/Sao_Paulo')::date;
begin
    if auth.uid() is null then raise exception 'Usuario nao autenticado'; end if;
    select count(*) into v_count
    from quiz_sessions
    where user_id = auth.uid()
      and (started_at at time zone 'America/Sao_Paulo')::date = v_today;
    if v_count >= v_limit then
        raise exception 'Limite de quizzes de hoje atingido. Volte apos a meia-noite.';
    end if;
    return start_quiz_session(auth.uid(), p_num_questions);
end;
$function$;

create or replace function public.app_quiz_status()
 returns table(plays integer, max_plays integer, next_at timestamp with time zone)
 language plpgsql stable security definer set search_path to 'public'
as $function$
declare
    v_limit int := 5;
    v_count int;
    v_today date := (now() at time zone 'America/Sao_Paulo')::date;
begin
    if auth.uid() is null then raise exception 'Usuario nao autenticado'; end if;
    select count(*) into v_count
    from quiz_sessions
    where user_id = auth.uid()
      and (started_at at time zone 'America/Sao_Paulo')::date = v_today;
    plays := v_count;
    max_plays := v_limit;
    if v_count >= v_limit then
        next_at := ((v_today + 1)::timestamp) at time zone 'America/Sao_Paulo';
    else
        next_at := now();
    end if;
    return next;
end;
$function$;;
