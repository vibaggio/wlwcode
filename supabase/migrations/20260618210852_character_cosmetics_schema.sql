-- configuracao do personagem do jogador
alter table profiles add column if not exists character jsonb not null
  default '{"body":"masc","outfit":"comum","cabeca":"none","mao":"none"}'::jsonb;

-- catalogo de pecas cosmeticas
create table if not exists cosmetic_items (
  key          text primary key,
  name         text not null,
  slot         text not null check (slot in ('outfit','cabeca','mao')),
  gender       text not null default 'any' check (gender in ('any','masc','fem')),
  source       text not null default 'loja' check (source in ('inicial','loja','conquista')),
  price        integer not null default 0,
  achievement_key text,
  sort_order   integer not null default 0,
  is_active    boolean not null default true
);
alter table cosmetic_items enable row level security;
drop policy if exists cosmetic_items_read on cosmetic_items;
create policy cosmetic_items_read on cosmetic_items for select using (true);

-- posse de pecas por jogador
create table if not exists player_cosmetics (
  user_id     uuid not null references auth.users(id) on delete cascade,
  item_key    text not null references cosmetic_items(key) on delete cascade,
  acquired_at timestamptz not null default now(),
  primary key (user_id, item_key)
);
alter table player_cosmetics enable row level security;
drop policy if exists player_cosmetics_read on player_cosmetics;
create policy player_cosmetics_read on player_cosmetics for select using (auth.uid() = user_id);

-- catalogo inicial
insert into cosmetic_items (key, name, slot, gender, source, price, sort_order) values
  ('comum','Roupa comum','outfit','any','inicial',0,1),
  ('jaleco','Jaleco de pesquisador','outfit','any','loja',300,2),
  ('colete','Colete de campo','outfit','any','loja',250,3),
  ('chapeu','Chapéu de campo','cabeca','any','loja',200,4),
  ('camera','Câmera','mao','any','loja',400,5)
on conflict (key) do update set
  name=excluded.name, slot=excluded.slot, gender=excluded.gender,
  source=excluded.source, price=excluded.price, sort_order=excluded.sort_order;;
