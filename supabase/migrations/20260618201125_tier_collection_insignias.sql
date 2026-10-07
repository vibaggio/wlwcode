delete from user_achievements where achievement_id = (select id from achievements where key='colecionador_grande');
delete from achievements where key='colecionador_grande';

insert into achievements (key, category, title, description, condition_type, target_value, reward_currency, condition_param, is_insignia, insignia_icon, insignia_tier, reward_avatar_key) values
  ('colecionador_bronze','colecao','Colecionador Iniciante','Tenha 25% de todas as espécies.','species_percent',25,50,null,true,'colecao','bronze',null),
  ('colecionador_prata','colecao','Colecionador Dedicado','Tenha 50% de todas as espécies.','species_percent',50,100,null,true,'colecao','prata',null),
  ('colecionador_ouro','colecao','Grande Colecionador','Tenha 75% de todas as espécies.','species_percent',75,150,null,true,'colecao','ouro','ins_colecao'),
  ('colecionador_diamante','colecao','Colecionador Lendário','Tenha 100% de todas as espécies.','species_percent',100,250,null,true,'colecao','diamante',null)
on conflict (key) do update set
  category=excluded.category, title=excluded.title, description=excluded.description,
  condition_type=excluded.condition_type, target_value=excluded.target_value,
  reward_currency=excluded.reward_currency, condition_param=excluded.condition_param,
  is_insignia=excluded.is_insignia, insignia_icon=excluded.insignia_icon,
  insignia_tier=excluded.insignia_tier, reward_avatar_key=excluded.reward_avatar_key;;
