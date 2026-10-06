create or replace view public.v_card_base
with (security_invoker=false) as
 SELECT ci.id AS card_id,
    ci.owner_id,
    ci.set_id,
    sp.id AS species_id,
    sp.common_name,
    sp.scientific_name,
    sp.family,
    COALESCE(ci.biome, sp.primary_biome) AS primary_biome,
    sp.conservation_status,
    ast.key AS art_style_key,
    ast.display_name AS art_style,
    ci.float_score,
    ci.rarity_tier,
    ci.serial_number,
    ci.is_promotional,
    ci.minted_at,
    COALESCE(( SELECT jsonb_object_agg(at.key, jsonb_build_object('display_name', at.display_name, 'value', cia.rolled_value, 'unit', at.unit, 'normalized', cia.normalized_value)) AS jsonb_object_agg
           FROM card_instance_attributes cia
             JOIN attributes at ON at.id = cia.attribute_id
          WHERE cia.card_instance_id = ci.id), '{}'::jsonb) AS attributes,
    COALESCE(COALESCE(ph.url, 'https://jpwaszlegloctkrfvpca.supabase.co/storage/v1/object/public/fotos/'::text || ph.storage_path), sp.image_url) AS image_url,
    COALESCE(pg.display_name, sp.photographer) AS photographer,
    COALESCE(ph.art_tier = 'alternativa'::text, false) AS alt_art,
    COALESCE(ph.focal_x, 50) AS focal_x,
    COALESCE(ph.focal_y, 50) AS focal_y
   FROM card_instances ci
     JOIN species sp ON sp.id = ci.species_id
     JOIN art_styles ast ON ast.id = ci.art_style_id
     LEFT JOIN photos ph ON ph.id = ci.photo_id
     LEFT JOIN photographers pg ON pg.id = ph.photographer_id;

create or replace view public.v_card_full
with (security_invoker=true) as
 SELECT ci.id AS card_id,
    ci.owner_id,
    ci.set_id,
    sp.id AS species_id,
    sp.common_name,
    sp.scientific_name,
    sp.family,
    COALESCE(ci.biome, sp.primary_biome) AS primary_biome,
    sp.conservation_status,
    ast.key AS art_style_key,
    ast.display_name AS art_style,
    ci.float_score,
    ci.rarity_tier,
    ci.serial_number,
    ci.is_promotional,
    ci.minted_at,
    COALESCE(( SELECT jsonb_object_agg(at.key, jsonb_build_object('display_name', at.display_name, 'value', cia.rolled_value, 'unit', at.unit, 'normalized', cia.normalized_value)) AS jsonb_object_agg
           FROM card_instance_attributes cia
             JOIN attributes at ON at.id = cia.attribute_id
          WHERE cia.card_instance_id = ci.id), '{}'::jsonb) AS attributes,
    COALESCE(COALESCE(ph.url, 'https://jpwaszlegloctkrfvpca.supabase.co/storage/v1/object/public/fotos/'::text || ph.storage_path), sp.image_url) AS image_url,
    COALESCE(pg.display_name, sp.photographer) AS photographer,
    COALESCE(ph.art_tier = 'alternativa'::text, false) AS alt_art,
    COALESCE(ph.focal_x, 50) AS focal_x,
    COALESCE(ph.focal_y, 50) AS focal_y
   FROM card_instances ci
     JOIN species sp ON sp.id = ci.species_id
     JOIN art_styles ast ON ast.id = ci.art_style_id
     LEFT JOIN photos ph ON ph.id = ci.photo_id
     LEFT JOIN photographers pg ON pg.id = ph.photographer_id;;
