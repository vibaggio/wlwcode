create or replace function public.app_extra_pack_price()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    v_uid uuid := auth.uid();
    v_base bigint;
    v_today date;
    v_bought_today int;
begin
    if v_uid is null then raise exception 'nao autenticado'; end if;
    select cost_currency into v_base from packs where is_free = false order by cost_currency limit 1;
    if v_base is null then return null; end if;
    v_today := (now() at time zone 'America/Sao_Paulo')::date;
    select count(*) into v_bought_today
      from pack_openings po
      where po.user_id = v_uid and po.source = 'purchased'
        and (po.opened_at at time zone 'America/Sao_Paulo')::date = v_today;
    return (v_base + 25 * v_bought_today)::integer;
end;
$function$;

grant execute on function public.app_extra_pack_price() to authenticated;;
