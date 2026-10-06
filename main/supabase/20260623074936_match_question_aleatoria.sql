create or replace function public.app_match_question(p_match uuid, p_card uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
    v_uid uuid := auth.uid();
    v_status text; v_hand uuid[]; v_used int;
    v_q uuid; v_qtext text; v_opts jsonb;
begin
    if v_uid is null then raise exception 'nao autenticado'; end if;
    select status, player_hand into v_status, v_hand
      from matches where id = p_match and player_id = v_uid;
    if not found then raise exception 'partida nao encontrada'; end if;
    if v_status <> 'em_andamento' then raise exception 'partida ja finalizada'; end if;
    if not (p_card = any(v_hand)) then raise exception 'carta fora da sua mao'; end if;
    select count(*) into v_used from match_rounds
        where match_id = p_match and player_card_id = p_card and played = true;
    if v_used > 0 then raise exception 'carta ja usada'; end if;

    -- pergunta aleatoria de todo o acervo, independente da especie da carta
    select id, question_text into v_q, v_qtext from quiz_questions
        where is_active order by random() limit 1;
    if v_q is null then
        return jsonb_build_object('question_id', null);
    end if;

    select jsonb_agg(jsonb_build_object('id', id, 'text', option_text) order by random())
      into v_opts from quiz_answer_options where question_id = v_q;

    return jsonb_build_object('question_id', v_q, 'text', v_qtext, 'options', coalesce(v_opts, '[]'::jsonb));
end;
$function$;;
