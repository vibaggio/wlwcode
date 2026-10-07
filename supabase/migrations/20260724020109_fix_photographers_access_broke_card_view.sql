-- A correcao anterior revogou TODO o acesso de authenticated a photographers, mas
-- v_card_full/v_card_base fazem LEFT JOIN nessa tabela para pegar o nome do fotografo.
-- Sem nenhum grant, a view inteira passou a falhar com "permission denied" para
-- qualquer jogador autenticado, derrubando a Colecao e a aba Jogar ao mesmo tempo.
--
-- Correcao precisa: a politica de linha volta a permitir ler qualquer fotografo
-- (necessario, o credito de qualquer fotografo precisa aparecer em qualquer carta),
-- mas o acesso por coluna fica restrito a id e display_name. contact_email e
-- payout_info continuam inacessiveis ao cliente, com ou sem RLS.

drop policy if exists photographers_self_select on public.photographers;

create policy photographers_public_read on public.photographers
  as permissive for select to authenticated
  using (true);

revoke all on public.photographers from authenticated;
grant select (id, display_name) on public.photographers to authenticated;;
