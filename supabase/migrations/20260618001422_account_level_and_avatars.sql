-- 1. Colunas de progressao no perfil
alter table profiles add column if not exists account_xp bigint not null default 0;
alter table profiles add column if not exists account_level int not null default 1;
alter table profiles add column if not exists level_rewarded int not null default 1;
alter table profiles add column if not exists avatar text;

-- 2. Catalogo de avatares e posse de avatares especiais
create table if not exists avatars (
  key text primary key,
  name text not null,
  category text not null default 'base',   -- base | level | achievement | purchase
  sort_order int not null default 0,
  is_active boolean not null default true
);

create table if not exists player_avatars (
  user_id uuid not null references profiles(id) on delete cascade,
  avatar_key text not null references avatars(key),
  acquired_at timestamptz not null default now(),
  primary key (user_id, avatar_key)
);

alter table avatars enable row level security;
alter table player_avatars enable row level security;

drop policy if exists avatars_read on avatars;
create policy avatars_read on avatars for select to authenticated using (true);

drop policy if exists player_avatars_read on player_avatars;
create policy player_avatars_read on player_avatars for select to authenticated using (user_id = auth.uid());

-- avatares base (bonequinhos por tema de cor) e marcos de nivel
insert into avatars (key, name, category, sort_order) values
  ('av1','Mata',    'base', 1),
  ('av2','Cerrado', 'base', 2),
  ('av3','Rio',     'base', 3),
  ('av4','Ceu',     'base', 4),
  ('av5','Terra',   'base', 5),
  ('av6','Sol',     'base', 6),
  ('av7','Noite',   'base', 7),
  ('av8','Areia',   'base', 8),
  ('lvl10','Marco nivel 10','level',10),
  ('lvl20','Marco nivel 20','level',20),
  ('lvl30','Marco nivel 30','level',30),
  ('lvl40','Marco nivel 40','level',40),
  ('lvl50','Marco nivel 50','level',50)
on conflict (key) do nothing;

-- 3. Concessao de XP, com niveis progressivos e premios
create or replace function public.grant_account_xp(p_user uuid, p_amount int)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_xp bigint; v_oldlvl int; v_rewarded int; v_newlvl int; v_lvl int; v_coins int := 0;
begin
  if p_user is null or p_amount is null or p_amount <= 0 then return; end if;

  update profiles
     set account_xp = coalesce(account_xp,0) + p_amount
   where id = p_user
  returning account_xp, coalesce(account_level,1), coalesce(level_rewarded,1)
       into v_xp, v_oldlvl, v_rewarded;
  if not found then return; end if;

  -- nivel pela curva: cumXP(L) = 20*(L-1)*(L+3)  ->  L = floor(-1 + sqrt(4 + xp/20))
  v_newlvl := greatest(1, floor(-1 + sqrt(4 + v_xp/20.0))::int);

  if v_newlvl > v_oldlvl then
    update profiles set account_level = v_newlvl where id = p_user;
  end if;

  if v_newlvl > v_rewarded then
    for v_lvl in (v_rewarded + 1) .. v_newlvl loop
      v_coins := v_coins + (10 + 5 * v_lvl);            -- moeda por nivel
      if v_lvl % 5 = 0 then v_coins := v_coins + 50; end if;   -- bonus a cada 5
      if v_lvl % 10 = 0 then                            -- a cada 10: avatar especial
        if exists (select 1 from avatars where key = 'lvl'||v_lvl and is_active) then
          insert into player_avatars (user_id, avatar_key)
          values (p_user, 'lvl'||v_lvl) on conflict do nothing;
        else
          v_coins := v_coins + 150;                     -- fallback se nao houver avatar definido
        end if;
      end if;
    end loop;
    update profiles
       set level_rewarded = v_newlvl,
           soft_currency  = soft_currency + v_coins
     where id = p_user;
    if v_coins > 0 then
      insert into currency_ledger (user_id, amount, reason) values (p_user, v_coins, 'level_up');
    end if;
  end if;
end;
$function$;

-- 4. Gatilhos que dao XP nas acoes (sem reescrever as funcoes grandes)
create or replace function public.tg_xp_match() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.status = 'finalizada' and old.status is distinct from 'finalizada' then
    perform grant_account_xp(new.player_id,
      case new.result when 'vitoria' then 30 when 'empate' then 15 else 10 end);
  end if;
  return new;
end;
$function$;
drop trigger if exists trg_xp_match on matches;
create trigger trg_xp_match after update on matches
for each row execute function tg_xp_match();

create or replace function public.tg_xp_quiz() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.completed_at is not null and old.completed_at is null then
    perform grant_account_xp(new.user_id, 10 + 5 * coalesce(new.correct_count,0));
  end if;
  return new;
end;
$function$;
drop trigger if exists trg_xp_quiz on quiz_sessions;
create trigger trg_xp_quiz after update on quiz_sessions
for each row execute function tg_xp_quiz();

create or replace function public.tg_xp_ledger() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.reason like 'mission:%' then
    perform grant_account_xp(new.user_id, case when new.reason = 'mission:all' then 25 else 10 end);
  elsif new.reason = 'daily_checkin' then
    perform grant_account_xp(new.user_id, 10);
  end if;
  return new;
end;
$function$;
drop trigger if exists trg_xp_ledger on currency_ledger;
create trigger trg_xp_ledger after insert on currency_ledger
for each row execute function tg_xp_ledger();

-- 5. Status da conta para a barra do topo
create or replace function public.app_account_status()
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_xp bigint; v_lvl int; v_avatar text; v_cum bigint; v_need int; v_into bigint;
begin
  if auth.uid() is null then raise exception 'nao autenticado'; end if;
  select coalesce(account_xp,0), coalesce(account_level,1), avatar
    into v_xp, v_lvl, v_avatar from profiles where id = auth.uid();
  if v_lvl is null then v_lvl := 1; end if;
  v_cum  := 20*(v_lvl-1)*(v_lvl+3);
  v_need := 40*v_lvl + 60;
  v_into := v_xp - v_cum; if v_into < 0 then v_into := 0; end if;
  return jsonb_build_object('level',v_lvl,'xp',v_xp,'xp_into',v_into,'xp_need',v_need,'avatar',v_avatar);
end;
$function$;

-- 6. Lista de avatares do jogador (catalogo + posse)
create or replace function public.app_my_avatars()
returns table(key text, name text, category text, sort_order int, owned boolean, selected boolean)
language sql security definer set search_path to 'public' as $function$
  select a.key, a.name, a.category, a.sort_order,
         (a.category = 'base' or pa.user_id is not null) as owned,
         (a.key = p.avatar) as selected
  from avatars a
  left join player_avatars pa on pa.avatar_key = a.key and pa.user_id = auth.uid()
  left join profiles p on p.id = auth.uid()
  where a.is_active
  order by a.category, a.sort_order, a.key;
$function$;

-- 7. Escolher avatar (valida posse)
create or replace function public.app_set_avatar(p_key text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare v_cat text;
begin
  if auth.uid() is null then raise exception 'nao autenticado'; end if;
  select category into v_cat from avatars where key = p_key and is_active;
  if v_cat is null then raise exception 'avatar invalido'; end if;
  if v_cat <> 'base' and not exists (
    select 1 from player_avatars where user_id = auth.uid() and avatar_key = p_key
  ) then raise exception 'avatar nao desbloqueado'; end if;
  update profiles set avatar = p_key where id = auth.uid();
  return p_key;
end;
$function$;

grant execute on function public.app_account_status() to authenticated;
grant execute on function public.app_my_avatars() to authenticated;
grant execute on function public.app_set_avatar(text) to authenticated;;
