-- O decremento antigo usava greatest(minted_count-1, 0), que evita erro mas tambem
-- esconde uma inconsistencia real (card_supply ja zerado enquanto uma carta daquela
-- combinacao ainda existia para queimar). Agora ele so decrementa quando ha o que
-- decrementar, e registra um aviso no log quando encontra uma linha zerada, sem nunca
-- impedir o jogador de devolver a carta (a queima da carta do jogador continua
-- funcionando normalmente mesmo nesse caso raro).
create or replace function public.burn_card(p_user_id uuid, p_card_id uuid)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
    v_owner   uuid;
    v_species uuid;
    v_art     uuid;
    v_set     uuid;
    v_rarity  text;
    v_listed  boolean;
    v_scrap   bigint;
    v_updated int;
begin
    select owner_id, species_id, art_style_id, set_id, rarity_tier
      into v_owner, v_species, v_art, v_set, v_rarity
    from card_instances where id = p_card_id for update;
    if not found then raise exception 'Carta nao encontrada'; end if;
    if v_owner is null or v_owner <> p_user_id then
        raise exception 'Esta carta nao pertence ao usuario';
    end if;

    select exists(select 1 from market_listings
        where card_instance_id = p_card_id and status = 'ativo') into v_listed;
    if v_listed then
        raise exception 'Cancele o anuncio no mercado antes de queimar a carta';
    end if;

    v_scrap := case v_rarity
        when 'comum' then 6
        when 'incomum' then 9
        when 'rara' then 12
        when 'lendaria' then 15
        when 'lendaria_reversa' then 15
        else 6
    end;

    insert into card_transactions (card_instance_id, from_user_id, event_type)
    values (p_card_id, p_user_id, 'burn');

    delete from card_instances where id = p_card_id;

    update card_supply set minted_count = minted_count - 1
    where species_id = v_species and art_style_id = v_art and set_id = v_set
      and minted_count > 0;
    get diagnostics v_updated = row_count;
    if v_updated = 0 and exists (
        select 1 from card_supply where species_id = v_species and art_style_id = v_art and set_id = v_set
    ) then
        raise warning 'card_supply ja estava com minted_count zerado ao queimar carta % (especie %, estilo %, set %)',
            p_card_id, v_species, v_art, v_set;
    end if;

    update profiles set soft_currency = soft_currency + v_scrap where id = p_user_id;
    insert into currency_ledger (user_id, amount, reason)
    values (p_user_id, v_scrap, 'burn_scrap');

    return v_scrap;
end;
$function$;;
