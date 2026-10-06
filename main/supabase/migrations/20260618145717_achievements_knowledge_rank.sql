CREATE OR REPLACE FUNCTION public.evaluate_achievements(p_user_id uuid)
 RETURNS TABLE(achievement_key text, title text, reward_currency bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    a                    record;
    v_total_cards        bigint;
    v_distinct_species   bigint;
    v_legendaries        bigint;
    v_packs              bigint;
    v_all_rarities_count bigint;
    v_progress           bigint;
    v_target             bigint;
    v_met                boolean;
    v_already            boolean;
    v_fam_total          bigint;
    v_fam_owned          bigint;
    v_pack               record;
    v_rank               bigint;
    i                    int;
begin
    select count(*),
           count(distinct species_id),
           count(*) filter (where rarity_tier = 'lendaria')
      into v_total_cards, v_distinct_species, v_legendaries
    from card_instances
    where owner_id = p_user_id;

    select count(*) into v_packs
    from pack_openings
    where user_id = p_user_id;

    select count(*) into v_all_rarities_count
    from get_species_progress(p_user_id)
    where all_rarities;

    select coalesce(knowledge_rank,0) into v_rank from profiles where id = p_user_id;

    for a in select * from achievements loop
        v_target   := coalesce(a.target_value, 1);
        v_progress := 0;
        v_met      := false;

        if a.condition_type = 'first_card' then
            v_target := 1; v_progress := least(v_total_cards, 1);
            v_met := v_total_cards >= 1;

        elsif a.condition_type = 'cards_total' then
            v_progress := v_total_cards;
            v_met := v_total_cards >= v_target;

        elsif a.condition_type = 'open_packs_total' then
            v_progress := v_packs;
            v_met := v_packs >= v_target;

        elsif a.condition_type = 'distinct_species' then
            v_progress := v_distinct_species;
            v_met := v_distinct_species >= v_target;

        elsif a.condition_type = 'first_legendary' then
            v_target := 1; v_progress := least(v_legendaries, 1);
            v_met := v_legendaries >= 1;

        elsif a.condition_type = 'legendaries_total' then
            v_progress := v_legendaries;
            v_met := v_legendaries >= v_target;

        elsif a.condition_type = 'species_all_rarities' then
            v_progress := v_all_rarities_count;
            v_met := v_all_rarities_count >= v_target;

        elsif a.condition_type = 'family_complete' then
            select count(*) into v_fam_total
            from species where family = a.condition_param;

            select count(distinct ci.species_id) into v_fam_owned
            from card_instances ci
            join species s on s.id = ci.species_id
            where ci.owner_id = p_user_id and s.family = a.condition_param;

            v_target := v_fam_total;
            v_progress := v_fam_owned;
            v_met := v_fam_total > 0 and v_fam_owned >= v_fam_total;

        elsif a.condition_type = 'knowledge_rank' then
            v_progress := v_rank;
            v_met := v_rank >= v_target;

        elsif a.condition_type = 'quiz_correct_difficulty' then
            select count(*) into v_progress
            from quiz_session_answers qa
            join quiz_sessions qs on qs.id = qa.session_id
            join quiz_questions qq on qq.id = qa.question_id
            where qs.user_id = p_user_id and qa.is_correct = true
              and qq.difficulty = a.condition_param;
            v_met := v_progress >= v_target;

        else
            continue;
        end if;

        select (ua.unlocked_at is not null) into v_already
        from user_achievements ua
        where ua.user_id = p_user_id and ua.achievement_id = a.id;
        v_already := coalesce(v_already, false);

        insert into user_achievements (user_id, achievement_id, progress, unlocked_at)
        values (p_user_id, a.id, v_progress, case when v_met then now() else null end)
        on conflict (user_id, achievement_id) do update
            set progress = excluded.progress,
                unlocked_at = case
                    when user_achievements.unlocked_at is not null then user_achievements.unlocked_at
                    when v_met then now()
                    else null
                end;

        if v_met and not v_already then
            if a.reward_currency > 0 then
                update profiles
                set soft_currency = soft_currency + a.reward_currency
                where id = p_user_id;

                insert into currency_ledger (user_id, amount, reason)
                values (p_user_id, a.reward_currency, 'conquista:' || a.key);
            end if;

            if a.reward_pack_id is not null then
                select * into v_pack from packs where id = a.reward_pack_id;
                if found then
                    for i in 1 .. v_pack.card_count loop
                        perform generate_card(p_user_id, v_pack.set_id, null);
                    end loop;
                    insert into pack_openings (user_id, pack_id, source)
                    values (p_user_id, v_pack.id, 'achievement');
                end if;
            end if;

            achievement_key := a.key;
            title           := a.title;
            reward_currency  := a.reward_currency;
            return next;
        end if;
    end loop;

    return;
end;
$function$;;
