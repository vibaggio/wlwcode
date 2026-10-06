-- marca as duas existentes como insignia e concede avatar
update achievements set is_insignia=true, insignia_icon='saber', insignia_tier='ouro', reward_avatar_key='ins_saber'
  where key='rank_mestre';
update achievements set is_insignia=true, insignia_icon='especie', insignia_tier='prata', reward_avatar_key='ins_especie'
  where key='especie_completa';

-- novas insignias
insert into achievements (key, category, title, description, condition_type, target_value, reward_currency, condition_param, is_insignia, insignia_icon, insignia_tier, reward_avatar_key) values
  ('arena_campeao','progressao','Campeão da Arena','Alcance 1200 de rating no desafio ranqueado.','ranked_rating',1200,150,null,true,'arena','ouro','ins_arena'),
  ('complecionista','colecao','Complecionista','Tenha todas as espécies em todas as raridades.','completionist',null,300,null,true,'completo','diamante','ins_completo'),
  ('familia_mestre','colecao','Mestre de uma Família','Complete todas as espécies de uma família com três ou mais espécies.','family_complete_any',1,120,null,true,'familia','prata','ins_familia'),
  ('bioma_guardiao','colecao','Guardião de um Bioma','Tenha 25 cartas de espécies de um mesmo bioma.','biome_cards_any',25,100,null,true,'bioma','prata','ins_bioma'),
  ('colecionador_grande','colecao','Grande Colecionador','Tenha 75% de todas as espécies.','species_percent',75,200,null,true,'colecao','ouro','ins_colecao')
on conflict (key) do update set
  category=excluded.category, title=excluded.title, description=excluded.description,
  condition_type=excluded.condition_type, target_value=excluded.target_value,
  reward_currency=excluded.reward_currency, condition_param=excluded.condition_param,
  is_insignia=excluded.is_insignia, insignia_icon=excluded.insignia_icon,
  insignia_tier=excluded.insignia_tier, reward_avatar_key=excluded.reward_avatar_key;;
