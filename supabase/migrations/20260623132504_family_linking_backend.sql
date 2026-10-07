-- Codigos de vinculo familiar (responsavel gera, crianca resgata)
create table if not exists public.family_link_codes (
  code text primary key,
  guardian_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  used_at timestamptz,
  used_by uuid references public.profiles(id) on delete set null
);
create index if not exists idx_family_link_codes_guardian on public.family_link_codes(guardian_id);
create index if not exists idx_family_link_codes_used_by on public.family_link_codes(used_by);

alter table public.family_link_codes enable row level security;
revoke all on public.family_link_codes from anon;
grant select, delete on public.family_link_codes to authenticated;

create policy family_codes_guardian_select on public.family_link_codes
  for select to authenticated using (guardian_id = auth.uid());
create policy family_codes_guardian_delete on public.family_link_codes
  for delete to authenticated using (guardian_id = auth.uid());

-- responsavel adulto gera um convite
create or replace function public.app_family_create_invite()
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_uid uuid := auth.uid(); v_adult boolean; v_code text;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  select coalesce(is_adult,false) into v_adult from legal_acceptance where user_id=v_uid;
  if not coalesce(v_adult,false) then
    return jsonb_build_object('ok', false, 'reason', 'apenas_responsavel_adulto');
  end if;
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));
    exit when not exists(select 1 from family_link_codes where code = v_code);
  end loop;
  insert into family_link_codes (code, guardian_id) values (v_code, v_uid);
  update profiles set account_type='responsavel'
    where id=v_uid and account_type='individual';
  return jsonb_build_object('ok', true, 'code', v_code,
                            'expires_at', (now() + interval '24 hours'));
end; $$;

-- crianca (ou o titular) resgata o convite e fica vinculada ao responsavel
create or replace function public.app_family_redeem_invite(p_code text)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_uid uuid := auth.uid(); v_guardian uuid; v_current uuid;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  select guardian_id into v_guardian from family_link_codes
    where code = upper(trim(p_code)) and used_at is null and expires_at > now();
  if v_guardian is null then return jsonb_build_object('ok', false, 'reason', 'codigo_invalido'); end if;
  if v_guardian = v_uid then return jsonb_build_object('ok', false, 'reason', 'proprio_codigo'); end if;
  select guardian_id into v_current from profiles where id = v_uid;
  if v_current is not null then return jsonb_build_object('ok', false, 'reason', 'ja_vinculado'); end if;

  update profiles set guardian_id = v_guardian, account_type = 'crianca' where id = v_uid;
  insert into parental_controls (child_id, updated_by) values (v_uid, v_guardian)
    on conflict (child_id) do nothing;
  update family_link_codes set used_at = now(), used_by = v_uid where code = upper(trim(p_code));
  return jsonb_build_object('ok', true);
end; $$;

-- responsavel lista seus filhos vinculados, com as permissoes
create or replace function public.app_family_children()
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_uid uuid := auth.uid(); v_out jsonb;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
            'id', p.id, 'username', p.username, 'birth_date', p.birth_date,
            'allow_purchases', coalesce(pc.allow_purchases,false),
            'allow_trades', coalesce(pc.allow_trades,false),
            'allow_ranked', coalesce(pc.allow_ranked,false),
            'allow_social', coalesce(pc.allow_social,false)
         ) order by p.username), '[]'::jsonb)
    into v_out
  from profiles p left join parental_controls pc on pc.child_id = p.id
  where p.guardian_id = v_uid;
  return v_out;
end; $$;

-- responsavel ajusta uma permissao de um filho
create or replace function public.app_family_set_control(p_child uuid, p_key text, p_value boolean)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_uid uuid := auth.uid(); v_ok boolean;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  if p_key not in ('allow_purchases','allow_trades','allow_ranked','allow_social') then
    return jsonb_build_object('ok', false, 'reason', 'chave_invalida');
  end if;
  select exists(select 1 from profiles where id=p_child and guardian_id=v_uid) into v_ok;
  if not v_ok then return jsonb_build_object('ok', false, 'reason', 'nao_e_seu_filho'); end if;
  insert into parental_controls (child_id, updated_by) values (p_child, v_uid)
    on conflict (child_id) do nothing;
  execute format('update parental_controls set %I = $1, updated_at = now(), updated_by = $2 where child_id = $3', p_key)
    using p_value, v_uid, p_child;
  return jsonb_build_object('ok', true);
end; $$;

-- responsavel desvincula um filho
create or replace function public.app_family_unlink(p_child uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_uid uuid := auth.uid(); v_ok boolean;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  select exists(select 1 from profiles where id=p_child and guardian_id=v_uid) into v_ok;
  if not v_ok then return jsonb_build_object('ok', false, 'reason', 'nao_e_seu_filho'); end if;
  delete from parental_controls where child_id = p_child;
  update profiles set guardian_id = null, account_type = 'individual' where id = p_child;
  return jsonb_build_object('ok', true);
end; $$;

revoke all on function public.app_family_create_invite() from anon, public;
grant execute on function public.app_family_create_invite() to authenticated;
revoke all on function public.app_family_redeem_invite(text) from anon, public;
grant execute on function public.app_family_redeem_invite(text) to authenticated;
revoke all on function public.app_family_children() from anon, public;
grant execute on function public.app_family_children() to authenticated;
revoke all on function public.app_family_set_control(uuid, text, boolean) from anon, public;
grant execute on function public.app_family_set_control(uuid, text, boolean) to authenticated;
revoke all on function public.app_family_unlink(uuid) from anon, public;
grant execute on function public.app_family_unlink(uuid) to authenticated;;
