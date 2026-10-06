delete from user_achievements where achievement_id = (select id from achievements where key='arena_campeao');
delete from achievements where key='arena_campeao';

insert into achievements (key, category, title, description, condition_type, target_value, reward_currency, condition_param, is_insignia, insignia_icon, insignia_tier, reward_avatar_key) values
  ('arena_bronze','progressao','Competidor da Arena','Alcance 1100 de rating no desafio ranqueado.','ranked_rating',1100,50,null,true,'arena','bronze',null),
  ('arena_prata','progressao','Veterano da Arena','Alcance 1200 de rating no desafio ranqueado.','ranked_rating',1200,100,null,true,'arena','prata',null),
  ('arena_ouro','progressao','Campeão da Arena','Alcance 1300 de rating no desafio ranqueado.','ranked_rating',1300,150,null,true,'arena','ouro','ins_arena'),
  ('arena_diamante','progressao','Lenda da Arena','Alcance 1450 de rating no desafio ranqueado.','ranked_rating',1450,250,null,true,'arena','diamante',null)
on conflict (key) do update set
  category=excluded.category, title=excluded.title, description=excluded.description,
  condition_type=excluded.condition_type, target_value=excluded.target_value,
  reward_currency=excluded.reward_currency, condition_param=excluded.condition_param,
  is_insignia=excluded.is_insignia, insignia_icon=excluded.insignia_icon,
  insignia_tier=excluded.insignia_tier, reward_avatar_key=excluded.reward_avatar_key;;
