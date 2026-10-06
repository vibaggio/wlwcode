-- remove a insignia antiga de bioma (por cartas) e seus registros
delete from user_achievements where achievement_id = (select id from achievements where key='bioma_guardiao');
delete from achievements where key='bioma_guardiao';

-- escada de niveis por especies distintas de um mesmo bioma
insert into achievements (key, category, title, description, condition_type, target_value, reward_currency, condition_param, is_insignia, insignia_icon, insignia_tier, reward_avatar_key) values
  ('bioma_bronze','colecao','Observador de Bioma','Colecione 3 espécies distintas de um mesmo bioma.','biome_species_any',3,50,null,true,'bioma','bronze',null),
  ('bioma_prata','colecao','Guardião de Bioma','Colecione 5 espécies distintas de um mesmo bioma.','biome_species_any',5,100,null,true,'bioma','prata',null),
  ('bioma_ouro','colecao','Mestre de Bioma','Colecione 7 espécies distintas de um mesmo bioma.','biome_species_any',7,150,null,true,'bioma','ouro','ins_bioma')
on conflict (key) do update set
  category=excluded.category, title=excluded.title, description=excluded.description,
  condition_type=excluded.condition_type, target_value=excluded.target_value,
  reward_currency=excluded.reward_currency, condition_param=excluded.condition_param,
  is_insignia=excluded.is_insignia, insignia_icon=excluded.insignia_icon,
  insignia_tier=excluded.insignia_tier, reward_avatar_key=excluded.reward_avatar_key;;
