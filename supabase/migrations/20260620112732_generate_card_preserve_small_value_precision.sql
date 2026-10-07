CREATE OR REPLACE FUNCTION public.generate_card(p_user_id uuid, p_set_id uuid, p_species_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
    v_species_id  uuid;
    v_art_id      uuid;
    v_common_id   uuid;
    v_r           numeric;
    v_float       numeric;
    v_sum         numeric := 0;
    v_count       int := 0;
    v_rarity      text;
    v_serial      int;
    v_card_id     uuid;
    v_supply_id   uuid;
    v_minted      int;
    v_max         int;
    v_norm        numeric;
    v_rolled      numeric;
    v_biome       text;
    v_photo_id    uuid;
    attr_row      record;
    v_attr_ids    uuid[]    := '{}';
    v_rolled_vals numeric[] := '{}';
    v_norm_vals   numeric[] := '{}';
    i             int;
begin
    -- 1. Especie
    --    No pacote (sorteio aleatorio) so entram especies com foto aprovada.
    --    Se, por algum motivo, nenhuma especie tiver foto, libera todas (protecao).
    if p_species_id is null then
        select id into v_species_id from species sp
        where exists (select 1 from photos p
                      where p.species_id = sp.id and p.status = 'aprovada')
        order by random() limit 1;
        if v_species_id is null then
            select id into v_species_id from species order by random() limit 1;
        end if;
    else
        v_species_id := p_species_id;
    end if;

    -- 1b. Bioma da carta
    select biome into v_biome
    from species_biomes
    where species_id = v_species_id
    order by random() limit 1;
    if v_biome is null then
        select primary_biome into v_biome from species where id = v_species_id;
    end if;

    -- 1c. Foto da carta: chance fixa de arte alternativa, quando a especie tiver
    v_photo_id := null;
    if random() < 0.06 then
        select id into v_photo_id from photos
        where species_id = v_species_id and status = 'aprovada' and art_tier = 'alternativa'
        order by random() limit 1;
    end if;
    if v_photo_id is null then
        select id into v_photo_id from photos
        where species_id = v_species_id and status = 'aprovada' and art_tier = 'padrao'
        order by random() limit 1;
    end if;
    if v_photo_id is null then
        select id into v_photo_id from photos
        where species_id = v_species_id and status = 'aprovada'
        order by random() limit 1;
    end if;

    -- 2. Estilo de arte por peso
    v_r := random();
    if v_r < 0.92 then
        v_art_id := (select id from art_styles where key = 'common_frame');
    elsif v_r < 0.965 then
        v_art_id := (select id from art_styles where key = 'holographic');
    elsif v_r < 0.99 then
        v_art_id := (select id from art_styles where key = 'full_art');
    else
        v_art_id := (select id from art_styles where key = 'holo_full_art');
    end if;

    v_common_id := (select id from art_styles where key = 'common_frame');

    -- 3. Reservar slot de oferta de forma atomica
    select id, minted_count, max_supply
      into v_supply_id, v_minted, v_max
    from card_supply
    where species_id = v_species_id and art_style_id = v_art_id and set_id = p_set_id
    for update;

    if found then
        if v_minted >= v_max then
            v_art_id := v_common_id;
            select id, minted_count, max_supply
              into v_supply_id, v_minted, v_max
            from card_supply
            where species_id = v_species_id and art_style_id = v_art_id and set_id = p_set_id
            for update;

            if found and v_minted >= v_max then
                raise exception 'Oferta esgotada para a especie % neste set', v_species_id;
            end if;
        end if;

        if v_supply_id is not null then
            v_serial := v_minted + 1;
            update card_supply set minted_count = minted_count + 1 where id = v_supply_id;
        end if;
    else
        v_serial := null;
    end if;

    -- 4. Sortear atributos
    for attr_row in
        select sar.attribute_id, sar.min_value, sar.max_value
        from species_attribute_ranges sar
        where sar.species_id = v_species_id
    loop
        v_norm   := random();
        v_rolled := attr_row.min_value + v_norm * (attr_row.max_value - attr_row.min_value);

        v_sum   := v_sum + v_norm;
        v_count := v_count + 1;

        v_attr_ids    := array_append(v_attr_ids, attr_row.attribute_id);
        -- Preserva a precisao de valores pequenos (ate 6 casas, sem zeros sobrando).
        -- Antes arredondava para 2 casas, o que zerava massas como 0,004 kg.
        v_rolled_vals := array_append(v_rolled_vals, trim_scale(round(v_rolled, 6)));
        v_norm_vals   := array_append(v_norm_vals, round(v_norm, 6));
    end loop;

    if v_count = 0 then
        raise exception 'Especie % nao tem faixas de atributos cadastradas', v_species_id;
    end if;

    -- 5. Float e raridade
    v_float  := round(v_sum / v_count, 6);
    v_rarity := rarity_from_float(v_float);

    -- 6. Cria a carta com bioma e foto
    insert into card_instances
        (species_id, art_style_id, set_id, owner_id, float_score, rarity_tier, serial_number, biome, photo_id)
    values
        (v_species_id, v_art_id, p_set_id, p_user_id, v_float, v_rarity, v_serial, v_biome, v_photo_id)
    returning id into v_card_id;

    -- 7. Atributos
    for i in 1 .. array_length(v_attr_ids, 1) loop
        insert into card_instance_attributes
            (card_instance_id, attribute_id, rolled_value, normalized_value)
        values
            (v_card_id, v_attr_ids[i], v_rolled_vals[i], v_norm_vals[i]);
    end loop;

    -- 8. Cunhagem
    insert into card_transactions (card_instance_id, to_user_id, event_type)
    values (v_card_id, p_user_id, 'mint');

    return v_card_id;
end;
$function$;;
