-- 1) remove a redundancia: fica so birth_date
alter table public.profiles drop column if exists birth_year;

-- 2) status legal v2 (nova versao de termos, nao afeta o site atual que usa v1)
create or replace function public.app_legal_status_v2()
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_user uuid := auth.uid(); v_ver text := 'v2-2026-06'; v_ok boolean; v_bd date; v_adult boolean;
begin
  if v_user is null then raise exception 'nao autenticado'; end if;
  select exists(select 1 from legal_acceptance where user_id=v_user and terms_version=v_ver) into v_ok;
  select birth_date into v_bd from profiles where id=v_user;
  select is_adult into v_adult from legal_acceptance where user_id=v_user and terms_version=v_ver;
  return jsonb_build_object('accepted', v_ok, 'version', v_ver,
                            'has_birth_date', v_bd is not null, 'is_adult', coalesce(v_adult,false));
end; $$;

-- 3) aceite v2: captura idade, deriva maioridade, exige consentimento do responsavel se menor
create or replace function public.app_accept_terms_v2(p_birth_date date, p_parental boolean default false)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_user uuid := auth.uid(); v_ver text := 'v2-2026-06'; v_age int; v_adult boolean;
begin
  if v_user is null then raise exception 'nao autenticado'; end if;
  if p_birth_date is null or p_birth_date > current_date
     or p_birth_date < current_date - interval '120 years' then
     return jsonb_build_object('ok', false, 'reason', 'data_invalida');
  end if;
  v_age := extract(year from age(p_birth_date))::int;
  v_adult := v_age >= 18;
  if (not v_adult) and (p_parental is not true) then
     return jsonb_build_object('ok', false, 'reason', 'consentimento_responsavel', 'is_adult', false);
  end if;
  update profiles
     set birth_date = p_birth_date,
         consent_at = case when not v_adult then now() else consent_at end,
         consent_version = case when not v_adult then v_ver else consent_version end
   where id = v_user;
  insert into legal_acceptance (user_id, terms_version, is_adult, parental_consent)
  values (v_user, v_ver, v_adult, case when not v_adult then true else false end)
  on conflict (user_id) do update
     set terms_version = excluded.terms_version,
         is_adult = excluded.is_adult,
         parental_consent = excluded.parental_consent,
         accepted_at = now();
  return jsonb_build_object('ok', true, 'is_adult', v_adult, 'version', v_ver);
end; $$;

revoke all on function public.app_legal_status_v2() from anon, public;
grant execute on function public.app_legal_status_v2() to authenticated;
revoke all on function public.app_accept_terms_v2(date, boolean) from anon, public;
grant execute on function public.app_accept_terms_v2(date, boolean) to authenticated;;
