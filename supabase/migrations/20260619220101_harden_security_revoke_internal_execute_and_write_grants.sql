-- 1) Furo critico: a funcao interna de XP nao pode ser chamada pelo cliente.
--    Gatilhos e funcoes SECURITY DEFINER que a usam rodam como dono e seguem funcionando.
revoke execute on function public.grant_account_xp(uuid, integer) from anon, authenticated, public;

-- 2) Higiene: funcoes de gatilho/internas nao devem ser chamaveis pelo cliente.
revoke execute on function public.handle_new_user() from anon, authenticated, public;
revoke execute on function public.tg_xp_ledger() from anon, authenticated, public;
revoke execute on function public.tg_xp_match() from anon, authenticated, public;
revoke execute on function public.tg_xp_quiz() from anon, authenticated, public;
revoke execute on function public.reset_for_trade_on_owner_change() from anon, authenticated, public;

-- 3) Defesa em profundidade: remover grants de escrita direta do cliente em todas as
--    tabelas do schema public. A aplicacao escreve via funcoes SECURITY DEFINER, e nao
--    existe nenhuma politica de escrita, entao isso nao afeta o funcionamento.
do $$
declare r record;
begin
  for r in select format('%I.%I', schemaname, tablename) as t
           from pg_tables where schemaname = 'public'
  loop
    execute format('revoke insert, update, delete on %s from anon, authenticated', r.t);
  end loop;
end $$;;
