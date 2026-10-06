-- Preco fixo do Pacote Extra em 150 moedas
update packs set cost_currency = 150 where is_free = false;

-- buy_pack volta a usar o preco fixo da tabela (sem escalonamento)
create or replace function public.buy_pack(p_user_id uuid, p_pack_id uuid)
 returns uuid[]
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
    v_pack  record;
    v_bal   bigint;
    v_cards uuid[] := '{}';
    v_card  uuid;
    i       int;
begin
    select * into v_pack from packs where id = p_pack_id;
    if not found then raise exception 'Pacote nao encontrado'; end if;
    if v_pack.is_free then raise exception 'Este pacote nao e comprado com moeda'; end if;

    select soft_currency into v_bal from profiles where id = p_user_id for update;
    if v_bal < v_pack.cost_currency then raise exception 'Saldo insuficiente'; end if;

    update profiles set soft_currency = soft_currency - v_pack.cost_currency where id = p_user_id;
    insert into currency_ledger (user_id, amount, reason)
    values (p_user_id, -v_pack.cost_currency, 'buy_pack');

    for i in 1 .. v_pack.card_count loop
        v_card := generate_card(p_user_id, v_pack.set_id, null);
        v_cards := array_append(v_cards, v_card);
    end loop;

    insert into pack_openings (user_id, pack_id, source)
    values (p_user_id, v_pack.id, 'purchased');

    return v_cards;
end;
$function$;

-- preco do Extra (fixo): menor pacote pago
create or replace function public.app_extra_pack_price()
 returns integer
 language sql
 security definer
 set search_path to 'public'
as $function$
  select cost_currency::integer from packs where is_free = false order by cost_currency limit 1;
$function$;

grant execute on function public.app_extra_pack_price() to authenticated;;
