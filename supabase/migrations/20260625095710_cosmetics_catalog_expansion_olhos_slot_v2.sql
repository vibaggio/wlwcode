-- 0) ampliar slots permitidos
alter table public.cosmetic_items drop constraint if exists cosmetic_items_slot_check;
alter table public.cosmetic_items add constraint cosmetic_items_slot_check
  check (slot = any (array['outfit'::text,'cabeca'::text,'mao'::text,'olhos'::text,'verso'::text]));

-- 1) app_set_character agora aceita e valida a camada 'olhos'
CREATE OR REPLACE FUNCTION public.app_set_character(p_character jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := auth.uid();
        v_body   text := coalesce(p_character->>'body','masc');
        v_outfit text := coalesce(p_character->>'outfit','comum');
        v_cabeca text := coalesce(p_character->>'cabeca','none');
        v_mao    text := coalesce(p_character->>'mao','none');
        v_olhos  text := coalesce(p_character->>'olhos','none');
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
  if v_olhos <> 'none' and not exists (
       select 1 from cosmetic_items ci left join player_cosmetics pc on pc.item_key=ci.key and pc.user_id=v_uid
       where ci.key=v_olhos and ci.slot='olhos' and ci.is_active and (ci.source='inicial' or pc.user_id is not null)
     ) then raise exception 'oculos nao disponivel'; end if;
  v_new := jsonb_build_object('body',v_body,'outfit',v_outfit,'cabeca',v_cabeca,'mao',v_mao,'olhos',v_olhos);
  update profiles set character = v_new where id = v_uid;
  return jsonb_build_object('character', v_new);
end; $function$;

-- 2) app_my_character: incluir 'olhos' no personagem padrao
CREATE OR REPLACE FUNCTION public.app_my_character()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := auth.uid(); v_char jsonb;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  select character into v_char from profiles where id = v_uid;
  return jsonb_build_object(
    'character', coalesce(v_char, '{"body":"masc","outfit":"comum","cabeca":"none","mao":"none","olhos":"none"}'::jsonb),
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
end; $function$;

-- 3) novas pecas
insert into cosmetic_items (key, name, slot, gender, source, price, sort_order, is_active) values
  ('moletom',  'Moletom',                                   'outfit', 'any', 'loja', 220, 10, true),
  ('regata',   'Regata',                                    'outfit', 'any', 'loja', 150, 11, true),
  ('poncho',   'Poncho de chuva',                           'outfit', 'any', 'loja', 320, 12, true),
  ('xadrez',   'Camisa xadrez',                             'outfit', 'any', 'loja', 240, 13, true),
  ('bone',     'Bon'||chr(233),                             'cabeca', 'any', 'loja', 160, 20, true),
  ('gorro',    'Gorro',                                     'cabeca', 'any', 'loja', 160, 21, true),
  ('bandana',  'Bandana',                                   'cabeca', 'any', 'loja', 120, 22, true),
  ('palha',    'Chap'||chr(233)||'u de palha',              'cabeca', 'any', 'loja', 200, 23, true),
  ('capacete', 'Capacete de campo',                         'cabeca', 'any', 'loja', 320, 24, true),
  ('binoculo', 'Bin'||chr(243)||'culos',                    'mao',    'any', 'loja', 300, 30, true),
  ('prancheta','Prancheta',                                 'mao',    'any', 'loja', 180, 31, true),
  ('lanterna', 'Lanterna',                                  'mao',    'any', 'loja', 220, 32, true),
  ('lupa',     'Lupa',                                      'mao',    'any', 'loja', 160, 33, true),
  ('oculos',   chr(211)||'culos de grau',                   'olhos',  'any', 'loja', 150, 40, true),
  ('sol',      chr(211)||'culos de sol',                    'olhos',  'any', 'loja', 200, 41, true),
  ('protecao', chr(211)||'culos de prote'||chr(231)||chr(227)||'o', 'olhos', 'any', 'loja', 280, 42, true)
on conflict (key) do nothing;;
