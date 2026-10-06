-- Duas chamadas simultaneas (duplo clique, duas abas, retentativa automatica) podiam
-- passar pela checagem de cooldown antes que qualquer uma registrasse a abertura,
-- rendendo dois pacotes gratis. O bloqueio consultivo por usuario serializa chamadas
-- concorrentes desta mesma funcao para o mesmo jogador: a segunda chamada espera a
-- primeira terminar (e sua transacao comitar) antes de checar o cooldown, ai sim ve
-- a abertura que acabou de ser registrada. E liberado sozinho ao fim da transacao.
create or replace function public.open_basic_pack(p_user_id uuid)
 returns uuid[]
 language plpgsql
 set search_path to 'public'
as $function$
declare
    v_pack    record;
    v_last    timestamptz;
    v_cards   uuid[] := '{}';
    v_card    uuid;
    i         int;
begin
    perform pg_advisory_xact_lock(hashtextextended('open_basic_pack:'||p_user_id::text, 0));

    select * into v_pack from packs where name = 'Pacote Basico' limit 1;
    if not found then
        raise exception 'Pacote Basico nao encontrado';
    end if;

    select max(opened_at) into v_last
    from pack_openings
    where user_id = p_user_id and pack_id = v_pack.id and source = 'free';

    if v_last is not null
       and v_pack.cooldown_hours is not null
       and now() < v_last + (v_pack.cooldown_hours || ' hours')::interval then
        raise exception 'Pacote ainda em espera. Disponivel em %',
            v_last + (v_pack.cooldown_hours || ' hours')::interval;
    end if;

    for i in 1 .. v_pack.card_count loop
        v_card  := generate_card(p_user_id, v_pack.set_id, null);
        v_cards := array_append(v_cards, v_card);
    end loop;

    insert into pack_openings (user_id, pack_id, source)
    values (p_user_id, v_pack.id, 'free');

    return v_cards;
end;
$function$;;
