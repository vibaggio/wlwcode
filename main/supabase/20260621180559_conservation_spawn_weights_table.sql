create table if not exists public.conservation_spawn_weights (
  status text primary key,
  weight double precision not null check (weight > 0)
);

alter table public.conservation_spawn_weights enable row level security;

comment on table public.conservation_spawn_weights is
  'Peso de sorteio de especies na abertura de pacote, por grau de conservacao. Quanto menor o peso, mais rara a especie aparece no jogo. Lida apenas pelas funcoes internas (definer); sem politica de RLS para clientes.';

insert into public.conservation_spawn_weights (status, weight) values
  ('Pouco preocupante',       1.0),
  ('Quase ameacada',          0.6),
  ('Vulneravel',              0.35),
  ('Em perigo',               0.2),
  ('Criticamente em perigo',  0.1)
on conflict (status) do update set weight = excluded.weight;;
