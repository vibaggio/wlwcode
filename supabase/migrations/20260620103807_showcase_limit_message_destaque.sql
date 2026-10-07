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
    if v_count >= 8 then raise exception 'Limite de 8 cartas em destaque'; end if;
  end if;
  update card_instances set showcase = p_on where id = p_card;
end; $$;;
