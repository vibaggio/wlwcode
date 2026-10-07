-- 1) Colunas novas (aditivas)
alter table card_instances add column if not exists showcase boolean not null default false;
alter table profiles      add column if not exists cards_public boolean not null default false;

-- indice para listar a vitrine de um jogador rapido
create index if not exists idx_card_instances_showcase on card_instances(owner_id) where showcase;

-- 2) Marcar/desmarcar carta na vitrine de orgulho (separado de "para troca"), limite 8
create or replace function public.app_set_showcase(p_card uuid, p_on boolean)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_owner uuid; v_count int;
begin
  if auth.uid() is null then raise exception 'Usuario nao autenticado'; end if;
  select owner_id into v_owner from card_instances where id = p_card;
  if not found then raise exception 'Carta nao encontrada'; end if;
  if v_owner <> auth.uid() then raise exception 'Esta carta nao e sua'; end if;
  if p_on then
    select count(*) into v_count from card_instances
      where owner_id = auth.uid() and showcase = true and id <> p_card;
    if v_count >= 8 then raise exception 'Limite de 8 cartas na vitrine'; end if;
  end if;
  update card_instances set showcase = p_on where id = p_card;
end; $$;

-- 3) Interruptor: mostrar a colecao inteira para outros (privada por padrao)
create or replace function public.app_set_cards_public(p_on boolean)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if auth.uid() is null then raise exception 'Usuario nao autenticado'; end if;
  update profiles set cards_public = p_on where id = auth.uid();
end; $$;

-- 4) Perfil publico (crachá): so dados publicos, sem e-mail nem moeda
create or replace function public.app_public_profile(p_username text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_prof record; v_rating int; v_total int; v_distinct int;
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

  return jsonb_build_object(
    'ok', true,
    'user_id', v_prof.id,
    'username', v_prof.username,
    'character', v_prof.character,
    'account_level', v_prof.account_level,
    'education_points', v_prof.education_points,
    'knowledge_rank', v_prof.knowledge_rank,
    'ranked_rating', v_rating,
    'distinct_species', v_distinct,
    'total_species', v_total,
    'member_since', v_prof.created_at,
    'cards_public', v_prof.cards_public,
    'is_me', (v_prof.id = auth.uid()),
    'insignias', coalesce((
      select jsonb_agg(jsonb_build_object('icon', a.insignia_icon, 'tier', a.insignia_tier,
                                           'title', a.title, 'description', a.description)
                       order by a.insignia_tier, a.title)
      from user_achievements ua join achievements a on a.id = ua.achievement_id
      where ua.user_id = v_prof.id and a.is_insignia = true
    ), '[]'::jsonb),
    'showcase', coalesce((
      select jsonb_agg(to_jsonb(cb))
      from card_instances ci join v_card_base cb on cb.card_id = ci.id
      where ci.owner_id = v_prof.id and ci.showcase = true
    ), '[]'::jsonb)
  );
end; $$;

-- 5) Cartas de um jogador, respeitando o interruptor (ou se for o proprio dono)
create or replace function public.app_player_cards(p_username text)
returns table(card_id uuid, common_name text, scientific_name text, art_style_key text,
              art_style text, float_score numeric, rarity_tier text, serial_number integer,
              conservation_status text, primary_biome text, attributes jsonb, image_url text)
language sql stable security definer set search_path to 'public' as $$
  select cb.card_id, cb.common_name, cb.scientific_name, cb.art_style_key, cb.art_style,
         cb.float_score, cb.rarity_tier, cb.serial_number, cb.conservation_status,
         cb.primary_biome, cb.attributes, cb.image_url
  from card_instances ci
  join profiles p     on p.id = ci.owner_id
  join v_card_base cb on cb.card_id = ci.id
  where p.username = trim(p_username)
    and (p.cards_public = true or ci.owner_id = auth.uid());
$$;

-- 6) Grants no padrao de seguranca: so logados executam
revoke execute on function public.app_set_showcase(uuid, boolean)  from public, anon;
revoke execute on function public.app_set_cards_public(boolean)    from public, anon;
revoke execute on function public.app_public_profile(text)         from public, anon;
revoke execute on function public.app_player_cards(text)           from public, anon;
grant execute on function public.app_set_showcase(uuid, boolean) to authenticated;
grant execute on function public.app_set_cards_public(boolean)   to authenticated;
grant execute on function public.app_public_profile(text)        to authenticated;
grant execute on function public.app_player_cards(text)          to authenticated;;
