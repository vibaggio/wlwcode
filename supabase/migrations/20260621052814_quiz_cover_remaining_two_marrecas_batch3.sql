do $$
declare
  q jsonb; qid uuid; sid uuid; opt jsonb;
  qs jsonb := $json$[
  {"sci":"Callonetta leucophrys","text":"A que família pertence a marreca-de-coleira?","diff":"facil","src":"Birds of the World","options":[{"t":"Anatidae","c":true},{"t":"Rheidae","c":false},{"t":"Accipitridae","c":false},{"t":"Trochilidae","c":false}]},
  {"sci":"Callonetta leucophrys","text":"A marreca-de-coleira costuma nidificar em:","diff":"dificil","src":"Birds of the World","options":[{"t":"Ocos de árvores","c":true},{"t":"Tocas escavadas no chão","c":false},{"t":"Ninhos flutuantes no mar","c":false},{"t":"Penhascos rochosos","c":false}]},
  {"sci":"Oxyura vittata","text":"A que família pertence a marreca-rabo-de-espinho?","diff":"facil","src":"Birds of the World","options":[{"t":"Anatidae","c":true},{"t":"Falconidae","c":false},{"t":"Ramphastidae","c":false},{"t":"Caprimulgidae","c":false}]},
  {"sci":"Oxyura vittata","text":"O nome rabo-de-espinho dessa marreca refere-se a:","diff":"media","src":"Birds of the World","options":[{"t":"As penas rígidas e pontudas da cauda","c":true},{"t":"Um bico cheio de espinhos","c":false},{"t":"Garras nas patas","c":false},{"t":"Uma crista espinhosa na cabeça","c":false}]}
  ]$json$::jsonb;
begin
  for q in select value from jsonb_array_elements(qs) loop
    select id into sid from species where scientific_name = q->>'sci';
    insert into quiz_questions (species_id, question_text, difficulty, source, time_limit_seconds, is_active)
      values (sid, q->>'text', q->>'diff', q->>'src', 20, true) returning id into qid;
    for opt in select value from jsonb_array_elements(q->'options') loop
      insert into quiz_answer_options (question_id, option_text, is_correct)
        values (qid, opt->>'t', (opt->>'c')::boolean);
    end loop;
  end loop;
end $$;;
