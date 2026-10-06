-- escada do ranqueamento do quiz: Aprendiz, Conhecedor, Especialista, Mestre
update achievements set is_insignia=true, insignia_icon='saber', insignia_tier='bronze'   where key='rank_aprendiz';
update achievements set is_insignia=true, insignia_icon='saber', insignia_tier='prata'     where key='rank_conhecedor';
update achievements set is_insignia=true, insignia_icon='saber', insignia_tier='ouro'      where key='rank_especialista';
update achievements set is_insignia=true, insignia_icon='saber', insignia_tier='diamante', reward_avatar_key='ins_saber' where key='rank_mestre';;
