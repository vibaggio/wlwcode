-- photographers guarda email de contato e dados de repasse (payout_info), que sao dados
-- pessoais/financeiros. A tabela estava com select liberado pra anon e authenticated,
-- e a politica de RLS permitia ler qualquer linha (using (true)). O frontend nunca
-- consulta esta tabela direto (o nome do fotografo chega ao cliente ja filtrado pelas
-- views de carta), entao travar o acesso nao muda nada no app.

revoke all on public.photographers from anon, authenticated;

drop policy if exists photographers_read on public.photographers;

-- defesa em profundidade: mesmo que o grant volte um dia, a politica sozinha ja restringe
-- cada fotografo a ver soh a propria linha. Leitura publica do nome continua vindo das views.
create policy photographers_self_select on public.photographers
  as permissive for select to authenticated
  using (user_id = (select auth.uid()));;
