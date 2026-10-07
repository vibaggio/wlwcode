-- 1) coluna de resgate
alter table public.user_achievements add column if not exists claimed_at timestamptz;

-- 2) backfill: o que ja esta desbloqueado ja foi concedido automaticamente no passado.
-- marca como resgatado para nao permitir resgate em dobro.
update public.user_achievements
   set claimed_at = unlocked_at
 where unlocked_at is not null and claimed_at is null;

-- 3) evaluate_achievements agora SO registra progresso e desbloqueio (nao concede mais nada)
create or replace function public.evaluate_achievements(p_user_id uuid)
 returns table(achievement_key text, title text, reward_currency bigint)
 language plpgsql security definer set search_path to 'public'
as $function$
declare
    a                    record;
    v_total_cards        bigint;
    v_distinct_species   bigint;
    v_legendaries        bigint;
    v_packs              bigint;
    v_all_rarities_count bigint;
    v_species_total      bigint;
    v_progress           bigint;
    v_target             bigint;
    v_met                boolean;
    v_already            boolean;
    v_fam_total          bigint;
    v_fam_owned          bigint;
    v_rank               bigint;
    v_pct                bigint;
begin
    select count(*),
           count(distinct species_id),
           count(*) filter (where rarity_tier = 'lendaria')
      into v_total_cards, v_distinct_species, v_legendaries
    from card_instances where owner_id = p_user_id;

    select count(*) into v_packs from pack_openings where user_id = p_user_id;
    select count(*) into v_all_rarities_count from get_species_progress(p_user_id) where all_rarities;
    select count(*) into v_species_total from get_species_progress(p_user_id);
    select coalesce(knowledge_rank,0) into v_rank from profiles where id = p_user_id;

    for a in select * from achievements loop
        v_target   := coalesce(a.target_value, 1);
        v_progress := 0;
        v_met      := false;

        if a.condition_type = 'first_card' then
            v_target := 1; v_progress := least(v_total_cards, 1); v_met := v_total_cards >= 1;
        elsif a.condition_type = 'cards_total' then
            v_progress := v_total_cards; v_met := v_total_cards >= v_target;
        elsif a.condition_type = 'open_packs_total' then
            v_progress := v_packs; v_met := v_packs >= v_target;
        elsif a.condition_type = 'distinct_species' then
            v_progress := v_distinct_species; v_met := v_distinct_species >= v_target;
        elsif a.condition_type = 'first_legendary' then
            v_target := 1; v_progress := least(v_legendaries, 1); v_met := v_legendaries >= 1;
        elsif a.condition_type = 'legendaries_total' then
            v_progress := v_legendaries; v_met := v_legendaries >= v_target;
        elsif a.condition_type = 'species_all_rarities' then
            v_progress := v_all_rarities_count; v_met := v_all_rarities_count >= v_target;
        elsif a.condition_type = 'family_complete' then
            select count(*) into v_fam_total from species where family = a.condition_param;
            select count(distinct ci.species_id) into v_fam_owned
            from card_instances ci join species s on s.id = ci.species_id
            where ci.owner_id = p_user_id and s.family = a.condition_param;
            v_target := v_fam_total; v_progress := v_fam_owned;
            v_met := v_fam_total > 0 and v_fam_owned >= v_fam_total;
        elsif a.condition_type = 'knowledge_rank' then
            v_progress := v_rank; v_met := v_rank >= v_target;
        elsif a.condition_type = 'quiz_correct_difficulty' then
            select count(*) into v_progress
            from quiz_session_answers qa
            join quiz_sessions qs on qs.id = qa.session_id
            join quiz_questions qq on qq.id = qa.question_id
            where qs.user_id = p_user_id and qa.is_correct = true
              and qq.difficulty = a.condition_param;
            v_met := v_progress >= v_target;
        elsif a.condition_type = 'ranked_rating' then
            select coalesce((select rating from ranked_teams where player_id = p_user_id), 0) into v_progress;
            v_met := v_progress >= v_target;
        elsif a.condition_type = 'completionist' then
            v_target := greatest(v_species_total, 1);
            v_progress := v_all_rarities_count;
            v_met := v_species_total > 0 and v_all_rarities_count >= v_species_total;
        elsif a.condition_type = 'species_percent' then
            v_pct := case when v_species_total > 0
                          then round(v_distinct_species * 100.0 / v_species_total) else 0 end;
            v_progress := v_pct; v_met := v_pct >= v_target;
        elsif a.condition_type = 'family_complete_any' then
            select coalesce(bool_or(fam.owned_distinct >= fam.total_species and fam.total_species >= 3), false)
              into v_met
            from (
              select s.family,
                     count(distinct s.id) as total_species,
                     count(distinct ci.species_id) as owned_distinct
              from species s
              left join card_instances ci on ci.species_id = s.id and ci.owner_id = p_user_id
              where s.family is not null
              group by s.family
            ) fam;
            v_met := coalesce(v_met, false);
            v_target := 1; v_progress := case when v_met then 1 else 0 end;
        elsif a.condition_type = 'biome_species_any' then
            select coalesce(max(z.cnt), 0) into v_progress
            from (
              select b.biome, count(distinct s.id) as cnt
              from species s
              join card_instances ci on ci.species_id = s.id and ci.owner_id = p_user_id
              cross join (values ('Amazonia'),('Mata Atlantica'),('Cerrado'),
                                 ('Caatinga'),('Pantanal'),('Pampa')) b(biome)
              where s.primary_biome ilike '%'||b.biome||'%'
              group by b.biome
            ) z;
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
                    when v_met then now() else null end;

        -- recompensa NAO e mais concedida aqui; fica para o resgate manual (app_claim_achievement)
        if v_met and not v_already then
            achievement_key := a.key;
            title           := a.title;
            reward_currency  := a.reward_currency;
            return next;
        end if;
    end loop;

    return;
end;
$function$;

-- 4) resgatar uma conquista: concede a recompensa e marca como resgatada (atomico)
create or replace function public.app_claim_achievement(p_achievement_id uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_uid uuid := auth.uid(); a record; v_ua record; v_pack record; i int;
        v_granted_pack boolean := false; v_granted_avatar boolean := false;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  select * into a from achievements where id = p_achievement_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'inexistente'); end if;
  select * into v_ua from user_achievements where user_id = v_uid and achievement_id = p_achievement_id;
  if not found or v_ua.unlocked_at is null then return jsonb_build_object('ok', false, 'reason', 'nao_desbloqueada'); end if;
  if v_ua.claimed_at is not null then return jsonb_build_object('ok', false, 'reason', 'ja_resgatada'); end if;

  update user_achievements set claimed_at = now()
   where user_id = v_uid and achievement_id = p_achievement_id and claimed_at is null;
  if not found then return jsonb_build_object('ok', false, 'reason', 'ja_resgatada'); end if;

  if coalesce(a.reward_currency,0) > 0 then
    update profiles set soft_currency = soft_currency + a.reward_currency where id = v_uid;
    insert into currency_ledger (user_id, amount, reason) values (v_uid, a.reward_currency, 'conquista:' || a.key);
  end if;
  if a.reward_pack_id is not null then
    select * into v_pack from packs where id = a.reward_pack_id;
    if found then
      for i in 1 .. v_pack.card_count loop perform generate_card(v_uid, v_pack.set_id, null); end loop;
      insert into pack_openings (user_id, pack_id, source) values (v_uid, v_pack.id, 'achievement');
      v_granted_pack := true;
    end if;
  end if;
  if a.reward_avatar_key is not null then
    insert into player_avatars (user_id, avatar_key) values (v_uid, a.reward_avatar_key)
      on conflict (user_id, avatar_key) do nothing;
    v_granted_avatar := true;
  end if;

  return jsonb_build_object('ok', true, 'title', a.title, 'currency', coalesce(a.reward_currency,0),
                            'pack', v_granted_pack, 'avatar', v_granted_avatar);
end; $$;

-- 5) resgatar tudo de uma vez
create or replace function public.app_claim_all_achievements()
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare r record; v_total bigint := 0; v_count int := 0; res jsonb;
begin
  if auth.uid() is null then raise exception 'nao autenticado'; end if;
  for r in
    select ua.achievement_id from user_achievements ua
    join achievements a on a.id = ua.achievement_id
    where ua.user_id = auth.uid() and ua.unlocked_at is not null and ua.claimed_at is null
      and (coalesce(a.reward_currency,0) > 0 or a.reward_pack_id is not null or a.reward_avatar_key is not null)
  loop
    res := app_claim_achievement(r.achievement_id);
    if coalesce((res->>'ok')::boolean, false) then
      v_count := v_count + 1;
      v_total := v_total + coalesce((res->>'currency')::bigint, 0);
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'claimed', v_count, 'currency', v_total);
end; $$;

-- 6) contagem do que ha para resgatar (para a bolinha)
create or replace function public.app_achievements_to_claim()
 returns integer language sql security definer set search_path to 'public'
as $$
  select count(*)::int
  from user_achievements ua
  join achievements a on a.id = ua.achievement_id
  where ua.user_id = auth.uid()
    and ua.unlocked_at is not null
    and ua.claimed_at is null
    and (coalesce(a.reward_currency,0) > 0 or a.reward_pack_id is not null or a.reward_avatar_key is not null);
$$;

revoke all on function public.app_claim_achievement(uuid) from anon, public;
grant execute on function public.app_claim_achievement(uuid) to authenticated;
revoke all on function public.app_claim_all_achievements() from anon, public;
grant execute on function public.app_claim_all_achievements() to authenticated;
revoke all on function public.app_achievements_to_claim() from anon, public;
grant execute on function public.app_achievements_to_claim() to authenticated;;
