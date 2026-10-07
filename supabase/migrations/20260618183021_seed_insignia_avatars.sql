insert into avatars (key, name, category, sort_order, is_active) values
  ('ins_saber','Sábio','insignia',101,true),
  ('ins_especie','Especialista','insignia',102,true),
  ('ins_arena','Campeão','insignia',103,true),
  ('ins_familia','Guardião da família','insignia',104,true),
  ('ins_bioma','Guardião do bioma','insignia',105,true),
  ('ins_colecao','Colecionador','insignia',106,true),
  ('ins_completo','Complecionista','insignia',107,true)
on conflict (key) do update set name=excluded.name, category=excluded.category, sort_order=excluded.sort_order, is_active=excluded.is_active;;
