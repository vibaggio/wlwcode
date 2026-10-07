insert into achievements (key, category, title, description, condition_type, target_value, reward_currency, condition_param) values
  ('rank_aprendiz','educacao','Aprendiz','Alcance 150 no ranqueamento de conhecimento.','knowledge_rank',150,40,null),
  ('rank_conhecedor','educacao','Conhecedor','Alcance 450 no ranqueamento de conhecimento.','knowledge_rank',450,80,null),
  ('rank_especialista','educacao','Especialista','Alcance 1000 no ranqueamento de conhecimento.','knowledge_rank',1000,150,null),
  ('rank_mestre','educacao','Mestre da Fauna','Alcance 2000 no ranqueamento de conhecimento.','knowledge_rank',2000,300,null),
  ('quiz_dificeis_10','educacao','Sangue-frio','Acerte 10 perguntas difíceis no quiz.','quiz_correct_difficulty',10,60,'dificil'),
  ('quiz_extremas_5','educacao','Mente extrema','Acerte 5 perguntas extremas no quiz.','quiz_correct_difficulty',5,120,'extremo')
on conflict (key) do update set
  category=excluded.category, title=excluded.title, description=excluded.description,
  condition_type=excluded.condition_type, target_value=excluded.target_value,
  reward_currency=excluded.reward_currency, condition_param=excluded.condition_param;;
