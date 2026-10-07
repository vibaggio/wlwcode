create or replace view public.v_card_base as
 select ci.id as card_id,
    ci.owner_id,
    ci.set_id,
    sp.id as species_id,
    sp.common_name,
    sp.scientific_name,
    sp.family,
    coalesce(ci.biome, sp.primary_biome) as primary_biome,
    sp.conservation_status,
    ast.key as art_style_key,
    ast.display_name as art_style,
    ci.float_score,
    ci.rarity_tier,
    ci.serial_number,
    ci.is_promotional,
    ci.minted_at,
    coalesce(( select jsonb_object_agg(at.key, jsonb_build_object('display_name', at.display_name, 'value', cia.rolled_value, 'unit', at.unit, 'normalized', cia.normalized_value)) as jsonb_object_agg
           from card_instance_attributes cia
             join attributes at on at.id = cia.attribute_id
          where cia.card_instance_id = ci.id), '{}'::jsonb) as attributes,
    coalesce(coalesce(ph.url, 'https://jpwaszlegloctkrfvpca.supabase.co/storage/v1/object/public/fotos/'::text || ph.storage_path), sp.image_url) as image_url,
    coalesce(pg.display_name, sp.photographer) as photographer,
    coalesce(ph.art_tier = 'alternativa'::text, false) as alt_art
   from card_instances ci
     join species sp on sp.id = ci.species_id
     join art_styles ast on ast.id = ci.art_style_id
     left join photos ph on ph.id = ci.photo_id
     left join photographers pg on pg.id = ph.photographer_id;

alter view public.v_card_base set (security_invoker = false);;
