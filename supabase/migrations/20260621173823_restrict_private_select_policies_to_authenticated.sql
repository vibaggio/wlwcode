-- Restringe leitura de dados pessoais e de partes ao papel autenticado.
-- O USING de cada politica (baseado em auth.uid()) permanece intacto.
alter policy album_entries_read_own     on public.album_entries            to authenticated;
alter policy alpha_welcome_read_own      on public.alpha_welcome            to authenticated;
alter policy cardattr_select_own         on public.card_instance_attributes to authenticated;
alter policy card_select_own             on public.card_instances           to authenticated;
alter policy ledger_select_own           on public.currency_ledger          to authenticated;
alter policy data_requests_read_own      on public.data_requests            to authenticated;
alter policy feedback_read_own           on public.feedback                 to authenticated;
alter policy market_select_all           on public.market_listings          to authenticated;
alter policy packopen_select_own         on public.pack_openings            to authenticated;
alter policy player_cosmetics_read       on public.player_cosmetics         to authenticated;
alter policy prof_select_own             on public.profiles                 to authenticated;
alter policy qsessans_select_own         on public.quiz_session_answers     to authenticated;
alter policy qsess_select_own            on public.quiz_sessions            to authenticated;
alter policy ranked_teams_own            on public.ranked_teams             to authenticated;
alter policy tradeitem_select_parties    on public.trade_offer_items        to authenticated;
alter policy trade_select_parties        on public.trade_offers             to authenticated;
alter policy userach_select_own          on public.user_achievements        to authenticated;;
