-- 1) Remover execucao das funcoes de jogo pelo papel anonimo (manter para logados)
do $$
declare
  fn text;
  r record;
  names text[] := array[
    'app_account_status','app_answer_quiz','app_burn_card','app_buy_cosmetic',
    'app_buy_listing','app_buy_pack','app_cancel_listing','app_cancel_trade',
    'app_create_trade','app_create_trade_by_name','app_extra_pack_price',
    'app_finish_quiz','app_get_session_questions','app_knowledge_status',
    'app_list_card','app_my_avatars','app_my_character','app_my_progress',
    'app_my_summary','app_next_free_pack','app_open_pack','app_paste_card',
    'app_paste_species_biome','app_player_binder','app_quiz_status',
    'app_respond_trade','app_set_avatar','app_set_character','app_set_for_trade',
    'app_set_username','app_start_quiz','app_transparency_totals'
  ];
begin
  foreach fn in array names loop
    for r in
      select p.oid::regprocedure::text as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = fn
    loop
      execute format('revoke all on function %s from anon, public', r.sig);
      execute format('grant execute on function %s to authenticated, service_role', r.sig);
    end loop;
  end loop;
end $$;

-- 2) Remover leitura anonima das views que sao apenas para usuarios logados
revoke select on
  public.v_education_ranking,
  public.v_ranked_ranking,
  public.v_market_active,
  public.v_ranked_history,
  public.v_trade_offers_detail
from anon;

-- 3) Catalogo de especies pode rodar com a permissao de quem consulta (limpa o lint sem quebrar nada)
alter view public.v_species_catalog set (security_invoker = on);;
