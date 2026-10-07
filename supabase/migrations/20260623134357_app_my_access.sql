-- acesso efetivo da conta atual: contas normais recebem tudo liberado;
-- conta crianca recebe o que o responsavel ligou
create or replace function public.app_my_access()
 returns jsonb language sql security definer set search_path to 'public'
as $$
  select jsonb_build_object(
    'is_child',        exists(select 1 from profiles where id=auth.uid() and guardian_id is not null),
    'allow_purchases', app_child_allowed('allow_purchases'),
    'allow_ranked',    app_child_allowed('allow_ranked'),
    'allow_social',    app_child_allowed('allow_social')
  );
$$;
revoke all on function public.app_my_access() from public, anon;
grant execute on function public.app_my_access() to authenticated;;
