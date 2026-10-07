create or replace function public.app_public_profile(p_username text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_prof record; v_rating int; v_total int; v_distinct int; v_know_pos int; v_arena_pos int;
begin
  select id, username, character, coalesce(account_level,1) as account_level,
         coalesce(education_points,0) as education_points, knowledge_rank,
         created_at, cards_public
    into v_prof
  from profiles where username = trim(p_username);
  if not found then return jsonb_build_object('ok', false, 'error', 'jogador_nao_encontrado'); end if;

  select rating into v_rating from ranked_teams where player_id = v_prof.id;
  select count(*) into v_total from species;
  select count(distinct species_id) into v_distinct from (
    select species_id from card_instances where owner_id = v_prof.id
    union
    select species_id from album_entries where user_id = v_prof.id
  ) s;

  -- posicao no ranking de conhecimento (competicao: quantos tem mais pontos + 1)
  select count(*)+1 into v_know_pos
    from profiles where coalesce(education_points,0) > v_prof.education_points;

  -- posicao na arena, apenas se o jogador tiver rating
  if v_rating is not null then
    select count(*)+1 into v_arena_pos from ranked_teams where rating > v_rating;
  else
    v_arena_pos := null;
  end if;

  return jsonb_build_object(
    'ok', true,
    'user_id', v_prof.id,
    'username', v_prof.username,
    'character', v_prof.character,
    'account_level', v_prof.account_level,
    'education_points', v_prof.education_points,
    'knowledge_rank', v_prof.knowledge_rank,
    'knowledge_pos', v_know_pos,
    'ranked_rating', v_rating,
    'arena_pos', v_arena_pos,
    'distinct_species', v_distinct,
    'total_species', v_total,
    'member_since', v_prof.created_at,
    'cards_public', v_prof.cards_public,
    'is_me', (v_prof.id = auth.uid()),
    'seals', '[]'::jsonb,
    'insignias', coalesce((
      select jsonb_agg(jsonb_build_object('icon', a.insignia_icon, 'tier', a.insignia_tier,
                                           'title', a.title, 'description', a.description)
                       order by a.insignia_tier, a.title)
      from user_achievements ua join achievements a on a.id = ua.achievement_id
      where ua.user_id = v_prof.id and a.is_insignia = true
        and ua.unlocked_at is not null
    ), '[]'::jsonb),
    'showcase', coalesce((
      select jsonb_agg(to_jsonb(cb))
      from card_instances ci join v_card_base cb on cb.card_id = ci.id
      where ci.owner_id = v_prof.id and ci.showcase = true
    ), '[]'::jsonb)
  );
end; $function$;;
