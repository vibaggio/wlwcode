create or replace function public.app_my_character()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); v_char jsonb;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  select character into v_char from profiles where id = v_uid;
  return jsonb_build_object(
    'character', coalesce(v_char, '{"body":"masc","outfit":"comum","cabeca":"none","mao":"none"}'::jsonb),
    'items', coalesce((
       select jsonb_agg(jsonb_build_object(
         'key', ci.key, 'name', ci.name, 'slot', ci.slot, 'gender', ci.gender,
         'source', ci.source, 'price', ci.price,
         'owned', (ci.source='inicial' or pc.user_id is not null)
       ) order by ci.sort_order)
       from cosmetic_items ci
       left join player_cosmetics pc on pc.item_key = ci.key and pc.user_id = v_uid
       where ci.is_active
    ), '[]'::jsonb)
  );
end; $$;

create or replace function public.app_set_character(p_character jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid();
        v_body   text := coalesce(p_character->>'body','masc');
        v_outfit text := coalesce(p_character->>'outfit','comum');
        v_cabeca text := coalesce(p_character->>'cabeca','none');
        v_mao    text := coalesce(p_character->>'mao','none');
        v_new jsonb;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  if v_body not in ('masc','fem') then raise exception 'corpo invalido'; end if;
  if v_outfit <> 'comum' and not exists (
       select 1 from cosmetic_items ci left join player_cosmetics pc on pc.item_key=ci.key and pc.user_id=v_uid
       where ci.key=v_outfit and ci.slot='outfit' and ci.is_active and (ci.source='inicial' or pc.user_id is not null)
     ) then raise exception 'roupa nao disponivel'; end if;
  if v_cabeca <> 'none' and not exists (
       select 1 from cosmetic_items ci left join player_cosmetics pc on pc.item_key=ci.key and pc.user_id=v_uid
       where ci.key=v_cabeca and ci.slot='cabeca' and ci.is_active and (ci.source='inicial' or pc.user_id is not null)
     ) then raise exception 'item de cabeca nao disponivel'; end if;
  if v_mao <> 'none' and not exists (
       select 1 from cosmetic_items ci left join player_cosmetics pc on pc.item_key=ci.key and pc.user_id=v_uid
       where ci.key=v_mao and ci.slot='mao' and ci.is_active and (ci.source='inicial' or pc.user_id is not null)
     ) then raise exception 'item de mao nao disponivel'; end if;
  v_new := jsonb_build_object('body',v_body,'outfit',v_outfit,'cabeca',v_cabeca,'mao',v_mao);
  update profiles set character = v_new where id = v_uid;
  return jsonb_build_object('character', v_new);
end; $$;

create or replace function public.app_buy_cosmetic(p_key text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); v_price int; v_source text; v_bal int;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  select price, source into v_price, v_source from cosmetic_items where key=p_key and is_active;
  if not found then raise exception 'peca nao encontrada'; end if;
  if v_source = 'inicial' then raise exception 'peca ja disponivel'; end if;
  if exists (select 1 from player_cosmetics where user_id=v_uid and item_key=p_key) then raise exception 'voce ja possui esta peca'; end if;
  if v_price <= 0 then raise exception 'peca nao esta a venda'; end if;
  select soft_currency into v_bal from profiles where id=v_uid for update;
  if v_bal < v_price then raise exception 'moedas insuficientes'; end if;
  update profiles set soft_currency = soft_currency - v_price where id=v_uid;
  insert into player_cosmetics (user_id, item_key) values (v_uid, p_key);
  insert into currency_ledger (user_id, amount, reason) values (v_uid, -v_price, 'cosmetic:'||p_key);
  return jsonb_build_object('ok', true, 'key', p_key, 'spent', v_price);
end; $$;

grant execute on function public.app_my_character() to authenticated;
grant execute on function public.app_set_character(jsonb) to authenticated;
grant execute on function public.app_buy_cosmetic(text) to authenticated;;
