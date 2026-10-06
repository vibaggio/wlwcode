do $$
declare
  r record;
  cols text;
  slug text;
begin
  for r in
    select c.oid, c.conrelid, c.conrelid::regclass::text as tbl
    from pg_constraint c
    join pg_namespace n on n.oid = c.connamespace
    where c.contype = 'f' and n.nspname = 'public'
      and c.conname in (
        'achievements_reward_pack_id_fkey','album_entries_species_id_fkey',
        'card_instance_attributes_attribute_id_fkey','card_instances_art_style_id_fkey',
        'card_instances_photo_id_fkey','card_instances_set_id_fkey',
        'card_supply_art_style_id_fkey','card_supply_set_id_fkey',
        'card_transactions_card_instance_id_fkey','card_transactions_from_user_id_fkey',
        'card_transactions_to_user_id_fkey','currency_ledger_user_id_fkey',
        'data_requests_user_id_fkey','market_listings_card_instance_id_fkey',
        'market_listings_seller_id_fkey','pack_openings_pack_id_fkey',
        'packs_set_id_fkey','photographers_user_id_fkey','photos_photographer_id_fkey',
        'player_avatars_avatar_key_fkey','player_cosmetics_item_key_fkey',
        'quiz_answer_options_question_id_fkey','quiz_questions_species_id_fkey',
        'quiz_session_answers_question_id_fkey','quiz_session_answers_selected_option_id_fkey',
        'quiz_session_answers_session_id_fkey','species_attribute_ranges_attribute_id_fkey',
        'trade_offer_items_card_instance_id_fkey','trade_offer_items_offered_by_fkey',
        'trade_offer_items_trade_offer_id_fkey','trade_offers_from_user_id_fkey',
        'trade_offers_to_user_id_fkey','user_achievements_achievement_id_fkey'
      )
  loop
    select string_agg(quote_ident(a.attname), ', ' order by k.ord),
           string_agg(a.attname, '_' order by k.ord)
      into cols, slug
    from unnest((select conkey from pg_constraint where oid = r.oid)) with ordinality as k(attnum, ord)
    join pg_attribute a on a.attrelid = r.conrelid and a.attnum = k.attnum;

    execute format('create index if not exists %I on %s (%s)',
                   'idx_' || replace(r.tbl, 'public.', '') || '_' || slug, r.tbl, cols);
  end loop;
end $$;;
