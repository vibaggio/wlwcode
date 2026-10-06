CREATE OR REPLACE FUNCTION public.app_ranked_play()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_me uuid := auth.uid();
    v_my_team jsonb; v_my_rating int;
    v_op uuid; v_op_team jsonb; v_op_rating int; v_op_name text;
    v_choices text[] := array['mass:high','mass:low','length:high','length:low','lifespan:high'];
    v_all_biomes text[];
    v_a jsonb[]; v_b jsonb[];
    v_pick text; v_attr text; v_dir text; v_cbiome text; v_dirsign numeric;
    v_val numeric; v_eff numeric; v_beff numeric; v_beff2 numeric;
    v_acard jsonb; v_bcard jsonb; v_aval numeric; v_bval numeric; v_aeff numeric; v_beffB numeric;
    v_abm boolean; v_bbm boolean; v_bi int; v_bi2 int;
    v_w text; v_as int := 0; v_bs int := 0; v_log jsonb := '[]'::jsonb;
    v_result text; v_exp_a numeric; v_score_a numeric;
    v_my_new int; v_op_new int;
    r int; i int;
begin
    if v_me is null then raise exception 'nao autenticado'; end if;

    select team, rating into v_my_team, v_my_rating from ranked_teams where player_id = v_me;
    if v_my_team is null then raise exception 'defina seu time ranqueado primeiro'; end if;

    select player_id, team, rating into v_op, v_op_team, v_op_rating
    from ranked_teams where player_id <> v_me order by random() limit 1;
    if v_op is null then raise exception 'ainda nao ha oponentes ranqueados'; end if;

    select username into v_op_name from profiles where id = v_op;
    select array_agg(distinct biome) into v_all_biomes from species_biomes;

    select array_agg(e) into v_a from jsonb_array_elements(v_my_team) e;
    select array_agg(e) into v_b from jsonb_array_elements(v_op_team) e;

    for r in 1..5 loop
        v_pick := v_choices[1 + floor(random()*5)::int];
        v_attr := split_part(v_pick,':',1);
        v_dir  := split_part(v_pick,':',2);
        v_dirsign := case when v_dir='high' then 1 else -1 end;

        v_cbiome := null;
        if v_all_biomes is not null and array_length(v_all_biomes,1) >= 1 and random() < 0.6 then
            v_cbiome := v_all_biomes[1 + floor(random()*array_length(v_all_biomes,1))::int];
        end if;

        v_bi := null; v_beff := null;
        for i in 1..array_length(v_a,1) loop
            if v_a[i] is not null then
                v_val := (v_a[i]->>v_attr)::numeric;
                v_eff := v_val * (case when v_cbiome is not null and (v_a[i]->>'biome')=v_cbiome then (1+v_dirsign*0.15) else 1 end);
                if v_beff is null or (v_dir='high' and v_eff>v_beff) or (v_dir='low' and v_eff<v_beff) then
                    v_beff := v_eff; v_bi := i;
                end if;
            end if;
        end loop;
        v_acard := v_a[v_bi]; v_a[v_bi] := null;
        v_aval := (v_acard->>v_attr)::numeric;
        v_abm  := (v_cbiome is not null and (v_acard->>'biome')=v_cbiome);
        v_aeff := v_aval * (case when v_abm then (1+v_dirsign*0.15) else 1 end);

        v_bi2 := null; v_beff2 := null;
        for i in 1..array_length(v_b,1) loop
            if v_b[i] is not null then
                v_val := (v_b[i]->>v_attr)::numeric;
                v_eff := v_val * (case when v_cbiome is not null and (v_b[i]->>'biome')=v_cbiome then (1+v_dirsign*0.15) else 1 end);
                if v_beff2 is null or (v_dir='high' and v_eff>v_beff2) or (v_dir='low' and v_eff<v_beff2) then
                    v_beff2 := v_eff; v_bi2 := i;
                end if;
            end if;
        end loop;
        v_bcard := v_b[v_bi2]; v_b[v_bi2] := null;
        v_bval  := (v_bcard->>v_attr)::numeric;
        v_bbm   := (v_cbiome is not null and (v_bcard->>'biome')=v_cbiome);
        v_beffB := v_bval * (case when v_bbm then (1+v_dirsign*0.15) else 1 end);

        if v_dir='high' then
            v_w := case when v_aeff>v_beffB then 'a' when v_aeff<v_beffB then 'b' else 'e' end;
        else
            v_w := case when v_aeff<v_beffB then 'a' when v_aeff>v_beffB then 'b' else 'e' end;
        end if;
        if v_w='a' then v_as := v_as+1; elsif v_w='b' then v_bs := v_bs+1; end if;

        v_log := v_log || jsonb_build_object(
            'round_no', r, 'attr', v_attr, 'dir', v_dir, 'biome', v_cbiome,
            'a', jsonb_build_object('name', v_acard->>'name', 'value', v_aval, 'biome_bonus', v_abm),
            'b', jsonb_build_object('name', v_bcard->>'name', 'value', v_bval, 'biome_bonus', v_bbm),
            'winner', v_w);
    end loop;

    v_result := case when v_as>v_bs then 'vitoria' when v_as<v_bs then 'derrota' else 'empate' end;

    v_exp_a := 1.0 / (1.0 + power(10.0, (v_op_rating - v_my_rating)/400.0));
    v_score_a := case v_result when 'vitoria' then 1.0 when 'empate' then 0.5 else 0.0 end;
    v_my_new := greatest(100, round(v_my_rating + 24*(v_score_a - v_exp_a))::int);
    v_op_new := greatest(100, round(v_op_rating + 24*((1-v_score_a) - (1-v_exp_a)))::int);

    update ranked_teams set rating = v_my_new,
        wins   = wins   + (case when v_result='vitoria' then 1 else 0 end),
        losses = losses + (case when v_result='derrota' then 1 else 0 end),
        draws  = draws  + (case when v_result='empate' then 1 else 0 end)
      where player_id = v_me;
    update ranked_teams set rating = v_op_new,
        wins   = wins   + (case when v_result='derrota' then 1 else 0 end),
        losses = losses + (case when v_result='vitoria' then 1 else 0 end),
        draws  = draws  + (case when v_result='empate' then 1 else 0 end)
      where player_id = v_op;

    insert into ranked_matches
        (player_a, player_b, a_score, b_score, result_a,
         a_rating_before, a_rating_after, b_rating_before, b_rating_after, log)
    values
        (v_me, v_op, v_as, v_bs, v_result,
         v_my_rating, v_my_new, v_op_rating, v_op_new, v_log);

    perform evaluate_achievements(v_me);

    return jsonb_build_object(
        'opponent', v_op_name,
        'opponent_rating', v_op_rating,
        'a_score', v_as, 'b_score', v_bs,
        'result', v_result,
        'rating_before', v_my_rating, 'rating_after', v_my_new,
        'delta', v_my_new - v_my_rating,
        'log', v_log
    );
end;
$function$;;
