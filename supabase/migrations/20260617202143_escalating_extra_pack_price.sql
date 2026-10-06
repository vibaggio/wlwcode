CREATE OR REPLACE FUNCTION public.buy_pack(p_user_id uuid, p_pack_id uuid)
 RETURNS uuid[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_pack         record;
    v_bal          bigint;
    v_cards        uuid[] := '{}';
    v_card         uuid;
    i              int;
    v_today        date;
    v_bought_today int;
    v_cost         bigint;
begin
    select * into v_pack from packs where id = p_pack_id;
    if not found then raise exception 'Pacote nao encontrado'; end if;
    if v_pack.is_free then raise exception 'Este pacote nao e comprado com moeda'; end if;

    -- O preco sobe 25 a cada pacote pago comprado no mesmo dia (fuso de Sao Paulo)
    v_today := (now() at time zone 'America/Sao_Paulo')::date;
    select count(*) into v_bought_today
      from pack_openings po
      where po.user_id = p_user_id and po.source = 'purchased'
        and (po.opened_at at time zone 'America/Sao_Paulo')::date = v_today;
    v_cost := v_pack.cost_currency + 25 * v_bought_today;

    select soft_currency into v_bal from profiles where id = p_user_id for update;
    if v_bal < v_cost then raise exception 'Saldo insuficiente'; end if;

    update profiles set soft_currency = soft_currency - v_cost where id = p_user_id;
    insert into currency_ledger (user_id, amount, reason)
    values (p_user_id, -v_cost, 'buy_pack');

    for i in 1 .. v_pack.card_count loop
        v_card := generate_card(p_user_id, v_pack.set_id, null);
        v_cards := array_append(v_cards, v_card);
    end loop;

    insert into pack_openings (user_id, pack_id, source)
    values (p_user_id, v_pack.id, 'purchased');

    return v_cards;
end;
$function$;;
