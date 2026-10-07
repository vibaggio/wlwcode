-- Funcao que faltava: o frontend ja chamava app_match_status (aba Hoje) mas ela nunca existiu.
-- Espelha exatamente a regra de limite diario usada em app_match_play (rolling 24h, ate 8 recompensadas).
create or replace function public.app_match_status()
returns table(rewarded_today integer, max_rewarded integer)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  return query
    select count(*)::int, 8
    from matches
    where player_id = v_uid and status = 'finalizada' and rewarded = true
      and finished_at > now() - interval '24 hours';
end;
$function$;

revoke all on function public.app_match_status() from public, anon;
grant execute on function public.app_match_status() to authenticated;;
