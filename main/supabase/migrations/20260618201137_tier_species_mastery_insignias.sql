-- bronze: 1 especie completa (era a insignia avulsa); tira o avatar, que sobe para o ouro
update achievements set
  is_insignia=true, insignia_icon='especie', insignia_tier='bronze',
  title='Mestre de uma Espécie', description='Tenha 1 espécie em todas as raridades.',
  reward_currency=50, reward_avatar_key=null
  where key='especie_completa';

-- degraus do meio
insert into achievements (key, category, title, description, condition_type, target_value, reward_currency, condition_param, is_insignia, insignia_icon, insignia_tier, reward_avatar_key) values
  ('especie_3','colecao','Mestre de 3 Espécies','Tenha 3 espécies em todas as raridades.','species_all_rarities',3,100,null,true,'especie','prata',null),
  ('especie_6','colecao','Mestre de 6 Espécies','Tenha 6 espécies em todas as raridades.','species_all_rarities',6,150,null,true,'especie','ouro','ins_especie')
on conflict (key) do update set
  category=excluded.category, title=excluded.title, description=excluded.description,
  condition_type=excluded.condition_type, target_value=excluded.target_value,
  reward_currency=excluded.reward_currency, condition_param=excluded.condition_param,
  is_insignia=excluded.is_insignia, insignia_icon=excluded.insignia_icon,
  insignia_tier=excluded.insignia_tier, reward_avatar_key=excluded.reward_avatar_key;

-- diamante: todas as especies em todas as raridades
update achievements set
  is_insignia=true, insignia_icon='completo', insignia_tier='diamante',
  title='Complecionista', description='Tenha todas as espécies em todas as raridades.',
  reward_currency=300, reward_avatar_key='ins_completo'
  where key='complecionista';;
