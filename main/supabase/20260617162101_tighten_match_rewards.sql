CREATE OR REPLACE FUNCTION public.app_match_play(p_match uuid, p_card uuid, p_question uuid DEFAULT NULL::uuid, p_option uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_uid uuid := auth.uid();
    v_status text; v_rounds int; v_cur int; v_hand uuid[];
    v_pscore int; v_nscore int;
    v_attr text; v_dir text; v_cbiome text;
    v_natval numeric; v_natname text; v_natimg text; v_natsp uuid; v_nbiome text;
    v_pval numeric; v_pbiome text;
    v_pbm boolean; v_nbm boolean; v_kb boolean := false; v_kbc boolean;
    v_dirsign numeric; v_f numeric := 0.15; v_pmult numeric; v_nmult numeric; v_peff numeric; v_neff numeric;
    v_winner text; v_used int;
    v_finished boolean := false;
    v_result text; v_reward int := 0; v_limit boolean := false; v_rewarded_today int;
    v_next jsonb := null;
begin
    if v_uid is null then raise exception 'nao autenticado'; end if;

    select status, rounds, current_round, player_hand, player_score, nature_score
      into v_status, v_rounds, v_cur, v_hand, v_pscore, v_nscore
    from matches where id = p_match and player_id = v_uid for update;
    if not found then raise exception 'partida nao encontrada'; end if;
    if v_status <> 'em_andamento' then raise exception 'partida ja finalizada'; end if;
    if not (p_card = any(v_hand)) then raise exception 'carta fora da sua mao'; end if;

    select count(*) into v_used from match_rounds
        where match_id = p_match and player_card_id = p_card and played = true;
    if v_used > 0 then raise exception 'carta ja usada'; end if;

    select challenge_attr, challenge_dir, challenge_biome,
           nature_value, nature_common_name, nature_image, nature_species_id, nature_biome
      into v_attr, v_dir, v_cbiome, v_natval, v_natname, v_natimg, v_natsp, v_nbiome
    from match_rounds where match_id = p_match and round_no = v_cur;

    select cia.rolled_value into v_pval
    from card_instance_attributes cia
    join attributes a on a.id = cia.attribute_id
    where cia.card_instance_id = p_card and a.key = v_attr;
    if v_pval is null then raise exception 'atributo da carta nao encontrado'; end if;

    select coalesce(ci.biome, sp.primary_biome) into v_pbiome
    from card_instances ci join species sp on sp.id = ci.species_id where ci.id = p_card;

    -- conhecimento
    if p_question is not null and p_option is not null then
        select is_correct into v_kbc from quiz_answer_options
            where id = p_option and question_id = p_question;
        v_kb := coalesce(v_kbc, false);
    end if;

    -- combinacoes de bioma
    v_pbm := (v_cbiome is not null and v_pbiome is not null and v_pbiome = v_cbiome);
    v_nbm := (v_cbiome is not null and v_nbiome is not null and v_nbiome = v_cbiome);

    -- direcao do reforco
    v_dirsign := case when v_dir = 'high' then 1 else -1 end;
    v_pmult := 1;
    if v_pbm then v_pmult := v_pmult * (1 + v_dirsign * v_f); end if;
    if v_kb  then v_pmult := v_pmult * (1 + v_dirsign * v_f); end if;
    v_nmult := 1;
    if v_nbm then v_nmult := v_nmult * (1 + v_dirsign * v_f); end if;

    v_peff := v_pval   * v_pmult;
    v_neff := v_natval * v_nmult;

    if v_dir = 'high' then
        v_winner := case when v_peff > v_neff then 'player'
                         when v_peff < v_neff then 'nature' else 'empate' end;
    else
        v_winner := case when v_peff < v_neff then 'player'
                         when v_peff > v_neff then 'nature' else 'empate' end;
    end if;

    update match_rounds
       set player_card_id = p_card, player_value = v_pval, player_biome = v_pbiome,
           kb_correct = v_kb, winner = v_winner, played = true
     where match_id = p_match and round_no = v_cur;

    if v_winner = 'player' then v_pscore := v_pscore + 1;
    elsif v_winner = 'nature' then v_nscore := v_nscore + 1; end if;

    if v_cur >= v_rounds then
        v_finished := true;
        v_result := case when v_pscore > v_nscore then 'vitoria'
                         when v_pscore < v_nscore then 'derrota' else 'empate' end;

        select count(*) into v_rewarded_today from matches
          where player_id = v_uid and status = 'finalizada' and rewarded = true
            and finished_at > now() - interval '24 hours';

        if v_rewarded_today < 8 then
            v_reward := case v_result when 'vitoria' then 15 when 'empate' then 6 else 2 end;
        else
            v_limit := true; v_reward := 0;
        end if;

        update matches
           set status='finalizada', current_round=v_cur, player_score=v_pscore, nature_score=v_nscore,
               result=v_result, rewarded=(v_reward>0), reward_coins=v_reward, finished_at=now()
         where id = p_match;

        if v_reward > 0 then
            update profiles set soft_currency = soft_currency + v_reward where id = v_uid;
            insert into currency_ledger (user_id, amount, reason) values (v_uid, v_reward, 'match_reward');
        end if;
    else
        update matches set current_round=v_cur+1, player_score=v_pscore, nature_score=v_nscore
         where id = p_match;
        select jsonb_build_object('round_no', v_cur+1,
                 'challenge', jsonb_build_object('attr', challenge_attr, 'dir', challenge_dir, 'biome', challenge_biome))
          into v_next
        from match_rounds where match_id = p_match and round_no = v_cur+1;
    end if;

    return jsonb_build_object(
        'round', jsonb_build_object(
            'round_no', v_cur, 'attr', v_attr, 'dir', v_dir, 'biome', v_cbiome,
            'player', jsonb_build_object('value', v_pval, 'biome', v_pbiome,
                       'biome_bonus', v_pbm, 'knowledge_bonus', v_kb),
            'nature', jsonb_build_object('name', v_natname, 'image', v_natimg, 'value', v_natval,
                       'biome', v_nbiome, 'biome_bonus', v_nbm),
            'winner', v_winner),
        'scores', jsonb_build_object('player', v_pscore, 'nature', v_nscore),
        'finished', v_finished,
        'next', v_next,
        'result', v_result,
        'reward_coins', v_reward,
        'limit_reached', v_limit
    );
end;
$function$;;
