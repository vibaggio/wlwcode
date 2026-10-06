-- 1. Liberar dificuldade 'extremo'
alter table quiz_questions drop constraint if exists quiz_questions_difficulty_check;
alter table quiz_questions add constraint quiz_questions_difficulty_check
  check (difficulty = any (array['facil'::text,'media'::text,'dificil'::text,'extremo'::text]));

-- 2. Resposta do quiz passa a devolver se acertou E qual era a opcao correta
drop function if exists public.app_answer_quiz(uuid, uuid, uuid, numeric);
create function public.app_answer_quiz(p_session uuid, p_question uuid, p_option uuid, p_time numeric default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_correct boolean; v_correct_opt uuid;
begin
  if not exists (select 1 from quiz_sessions where id = p_session and user_id = auth.uid()) then
    raise exception 'Sessao nao encontrada';
  end if;
  v_correct := answer_quiz_question(p_session, p_question, p_option, p_time);
  select id into v_correct_opt
    from quiz_answer_options where question_id = p_question and is_correct = true limit 1;
  return jsonb_build_object('correct', v_correct, 'correct_option_id', v_correct_opt);
end;
$function$;

grant execute on function public.app_answer_quiz(uuid, uuid, uuid, numeric) to authenticated;;
