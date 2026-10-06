-- campo de pais do titular, base para regras por regiao no futuro (inerte ate ser capturado)
alter table public.profiles add column if not exists country text;
comment on column public.profiles.country is 'Pais do titular (ISO 3166-1 alpha-2, ex.: BR; OTHER = outro). Capturado no aceite; base para regras por regiao.';

-- substitui o aceite v2 por uma versao que tambem grava o pais.
-- a versao de 3 argumentos com default cobre as chamadas antigas de 2 argumentos.
drop function if exists public.app_accept_terms_v2(date, boolean);
create or replace function public.app_accept_terms_v2(p_birth_date date, p_parental boolean default false, p_country text default null)
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
         country = coalesce(nullif(p_country,''), country),
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
end;
$$;
revoke all on function public.app_accept_terms_v2(date, boolean, text) from anon, public;
grant execute on function public.app_accept_terms_v2(date, boolean, text) to authenticated;;
