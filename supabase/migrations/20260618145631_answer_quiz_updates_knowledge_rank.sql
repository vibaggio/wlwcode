CREATE OR REPLACE FUNCTION public.answer_quiz_question(p_session_id uuid, p_question_id uuid, p_selected_option_id uuid, p_time_taken numeric DEFAULT NULL::numeric)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_completed    timestamptz;
    v_uid          uuid;
    v_belongs      boolean;
    v_opt_question uuid;
    v_opt_correct  boolean;
    v_limit        int;
    v_correct      boolean;
    v_prev         uuid;
    v_diff         text;
    v_delta        int := 0;
begin
    select completed_at, user_id into v_completed, v_uid from quiz_sessions where id = p_session_id;
    if not found then
        raise exception 'Sessao nao encontrada';
    end if;
    if v_completed is not null then
        raise exception 'Sessao ja finalizada';
    end if;

    select exists(
        select 1 from quiz_session_answers
        where session_id = p_session_id and question_id = p_question_id
    ) into v_belongs;
    if not v_belongs then
        raise exception 'Esta pergunta nao pertence a sessao';
    end if;

    select question_id, is_correct into v_opt_question, v_opt_correct
    from quiz_answer_options where id = p_selected_option_id;
    if not found or v_opt_question <> p_question_id then
        raise exception 'Opcao invalida para esta pergunta';
    end if;

    select time_limit_seconds, difficulty into v_limit, v_diff from quiz_questions where id = p_question_id;
    v_correct := v_opt_correct and (p_time_taken is null or p_time_taken <= v_limit);

    -- resposta anterior (para nao recontar ranqueamento numa re-submissao)
    select selected_option_id into v_prev
    from quiz_session_answers where session_id = p_session_id and question_id = p_question_id;

    update quiz_session_answers
       set selected_option_id  = p_selected_option_id,
           is_correct          = v_correct,
           time_taken_seconds  = p_time_taken
    where session_id = p_session_id and question_id = p_question_id;

    -- ranqueamento de conhecimento: acerto soma por dificuldade; erro tira nas mais dificeis
    if v_prev is null and v_uid is not null then
        if v_correct then
            v_delta := case v_diff when 'facil' then 5 when 'media' then 10
                                   when 'dificil' then 20 when 'extremo' then 35 else 5 end;
        else
            v_delta := case v_diff when 'dificil' then -10 when 'extremo' then -20 else 0 end;
        end if;
        if v_delta <> 0 then
            update profiles
               set knowledge_rank = greatest(0, coalesce(knowledge_rank,0) + v_delta)
             where id = v_uid;
        end if;
    end if;

    return v_correct;
end;
$function$;;
