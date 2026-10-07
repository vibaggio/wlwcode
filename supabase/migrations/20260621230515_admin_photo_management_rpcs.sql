-- Listar fotos para o painel de admin
create or replace function public.app_admin_list_photos(p_only_pending boolean default false)
returns table(
  photo_id uuid, species_id uuid, common_name text, scientific_name text,
  url text, status text, art_tier text, is_primary boolean,
  focal_x smallint, focal_y smallint, photographer text
)
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not exists (select 1 from admins where user_id = auth.uid()) then
    raise exception 'Acesso restrito';
  end if;
  return query
  select p.id, p.species_id, s.common_name, s.scientific_name,
         coalesce(p.url, 'https://jpwaszlegloctkrfvpca.supabase.co/storage/v1/object/public/fotos/' || p.storage_path) as url,
         p.status, p.art_tier, p.is_primary, p.focal_x, p.focal_y,
         pg.display_name as photographer
  from photos p
  join species s on s.id = p.species_id
  left join photographers pg on pg.id = p.photographer_id
  where (not p_only_pending or p.status = 'pendente')
  order by s.common_name, p.art_tier, p.id;
end;
$function$;

-- Definir o ponto focal de uma foto
create or replace function public.app_admin_set_photo_focus(p_photo_id uuid, p_x integer, p_y integer)
returns void
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not exists (select 1 from admins where user_id = auth.uid()) then
    raise exception 'Acesso restrito';
  end if;
  if p_x is null or p_y is null or p_x < 0 or p_x > 100 or p_y < 0 or p_y > 100 then
    raise exception 'Valores de foco invalidos (0 a 100)';
  end if;
  update photos set focal_x = p_x::smallint, focal_y = p_y::smallint where id = p_photo_id;
  if not found then raise exception 'Foto nao encontrada'; end if;
end;
$function$;

-- Aprovar / rejeitar / voltar a pendente
create or replace function public.app_admin_set_photo_status(p_photo_id uuid, p_status text)
returns void
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not exists (select 1 from admins where user_id = auth.uid()) then
    raise exception 'Acesso restrito';
  end if;
  if p_status not in ('pendente','aprovada','rejeitada') then
    raise exception 'Status invalido';
  end if;
  update photos set status = p_status, reviewed_at = now() where id = p_photo_id;
  if not found then raise exception 'Foto nao encontrada'; end if;
end;
$function$;

revoke all on function public.app_admin_list_photos(boolean) from anon, public;
revoke all on function public.app_admin_set_photo_focus(uuid, integer, integer) from anon, public;
revoke all on function public.app_admin_set_photo_status(uuid, text) from anon, public;
grant execute on function public.app_admin_list_photos(boolean) to authenticated;
grant execute on function public.app_admin_set_photo_focus(uuid, integer, integer) to authenticated;
grant execute on function public.app_admin_set_photo_status(uuid, text) to authenticated;;
