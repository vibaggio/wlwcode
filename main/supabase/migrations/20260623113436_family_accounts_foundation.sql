-- Fundacao para contas familiares (responsavel + crianca). Inerte: o app ainda nao le isto.

alter table public.profiles
  add column if not exists account_type text not null default 'individual',
  add column if not exists guardian_id uuid,
  add column if not exists birth_year smallint,
  add column if not exists consent_at timestamptz,
  add column if not exists consent_by uuid,
  add column if not exists consent_version text;

alter table public.profiles
  add constraint profiles_account_type_chk
    check (account_type in ('individual','responsavel','crianca')),
  add constraint profiles_birth_year_chk
    check (birth_year is null or (birth_year between 1900 and 2100)),
  add constraint profiles_guardian_fk
    foreign key (guardian_id) references public.profiles(id) on delete set null,
  add constraint profiles_consent_by_fk
    foreign key (consent_by) references public.profiles(id) on delete set null;

create index if not exists idx_profiles_guardian on public.profiles(guardian_id);
create index if not exists idx_profiles_consent_by on public.profiles(consent_by);

comment on column public.profiles.account_type is 'individual = adulto solo; responsavel = adulto que gerencia criancas; crianca = perfil de menor sob um responsavel';
comment on column public.profiles.guardian_id is 'Para perfis crianca, aponta para o profile do responsavel';
comment on column public.profiles.birth_year is 'Ano de nascimento, base para faixa etaria e gating de menor';
comment on column public.profiles.consent_at is 'Quando o responsavel deu consentimento (LGPD art. 14) para o perfil crianca';
comment on column public.profiles.consent_by is 'Profile do responsavel que deu o consentimento';

create table if not exists public.parental_controls (
  child_id uuid primary key references public.profiles(id) on delete cascade,
  allow_purchases boolean not null default false,
  allow_trades boolean not null default false,
  allow_ranked boolean not null default false,
  allow_social boolean not null default false,
  daily_time_limit_min integer,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null
);

create index if not exists idx_parental_controls_updated_by on public.parental_controls(updated_by);

comment on table public.parental_controls is 'Permissoes parentais por perfil crianca. Padrao restritivo. Ainda nao consumido pelo app.';

alter table public.parental_controls enable row level security;

revoke all on public.parental_controls from anon;
grant select, update on public.parental_controls to authenticated;

create policy parental_controls_child_select on public.parental_controls
  for select to authenticated
  using (child_id = auth.uid());

create policy parental_controls_guardian_select on public.parental_controls
  for select to authenticated
  using (exists (select 1 from public.profiles c
                 where c.id = parental_controls.child_id and c.guardian_id = auth.uid()));

create policy parental_controls_guardian_update on public.parental_controls
  for update to authenticated
  using (exists (select 1 from public.profiles c
                 where c.id = parental_controls.child_id and c.guardian_id = auth.uid()))
  with check (exists (select 1 from public.profiles c
                 where c.id = parental_controls.child_id and c.guardian_id = auth.uid()));;
