-- visibilidade por campo, separada da permissao de acao
alter table public.parental_controls
  add column if not exists show_purchases boolean not null default true,
  add column if not exists show_ranked    boolean not null default true;

-- acesso efetivo: contas normais recebem tudo visivel e liberado;
-- conta crianca recebe visibilidade e permissao definidas pelo responsavel
create or replace function public.app_my_access()
 returns jsonb language sql security definer set search_path to 'public'
as $$
  select case
    when not exists (select 1 from profiles where id=auth.uid() and guardian_id is not null)
      then jsonb_build_object('is_child', false,
             'show_purchases', true, 'allow_purchases', true,
             'show_ranked', true, 'allow_ranked', true)
    else coalesce(
      (select jsonb_build_object('is_child', true,
         'show_purchases',  coalesce(pc.show_purchases, true),
         'allow_purchases', coalesce(pc.allow_purchases, false),
         'show_ranked',     coalesce(pc.show_ranked, true),
         'allow_ranked',    coalesce(pc.allow_ranked, false))
       from parental_controls pc where pc.child_id = auth.uid()),
      jsonb_build_object('is_child', true,
         'show_purchases', true, 'allow_purchases', false,
         'show_ranked', true, 'allow_ranked', false))
  end;
$$;

-- lista de filhos do responsavel passa a incluir visibilidade
create or replace function public.app_family_children()
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_uid uuid := auth.uid(); v_out jsonb;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
            'id', p.id, 'username', p.username, 'birth_date', p.birth_date,
            'show_purchases',  coalesce(pc.show_purchases,true),
            'allow_purchases', coalesce(pc.allow_purchases,false),
            'show_ranked',     coalesce(pc.show_ranked,true),
            'allow_ranked',    coalesce(pc.allow_ranked,false)
         ) order by p.username), '[]'::jsonb)
    into v_out
  from profiles p left join parental_controls pc on pc.child_id = p.id
  where p.guardian_id = v_uid;
  return v_out;
end; $$;

-- ajuste de controle passa a aceitar tambem as chaves de visibilidade
create or replace function public.app_family_set_control(p_child uuid, p_key text, p_value boolean)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_uid uuid := auth.uid(); v_ok boolean;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  if p_key not in ('allow_purchases','allow_ranked','allow_trades','allow_social','show_purchases','show_ranked') then
    return jsonb_build_object('ok', false, 'reason', 'chave_invalida');
  end if;
  select exists(select 1 from profiles where id=p_child and guardian_id=v_uid) into v_ok;
  if not v_ok then return jsonb_build_object('ok', false, 'reason', 'nao_e_seu_filho'); end if;
  insert into parental_controls (child_id, updated_by) values (p_child, v_uid)
    on conflict (child_id) do nothing;
  execute format('update parental_controls set %I = $1, updated_at = now(), updated_by = $2 where child_id = $3', p_key)
    using p_value, v_uid, p_child;
  return jsonb_build_object('ok', true);
end; $$;;
