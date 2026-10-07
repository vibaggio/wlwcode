do $$
declare
  q jsonb;
  qid uuid;
  sid uuid;
  opt jsonb;
  qs jsonb := $json$[
  {"sci":"Hydropsalis torquata","text":"A que família pertence o bacurau-tesoura?","diff":"media","src":"Birds of the World","options":[{"t":"Caprimulgidae","c":true},{"t":"Trochilidae","c":false},{"t":"Falconidae","c":false},{"t":"Anatidae","c":false}]},
  {"sci":"Hydropsalis torquata","text":"Qual é o hábito predominante do bacurau-tesoura?","diff":"facil","src":"Birds of the World","options":[{"t":"Noturno e crepuscular","c":true},{"t":"Diurno","c":false},{"t":"Ativo só ao meio-dia","c":false},{"t":"Subaquático","c":false}]},
  {"sci":"Hydropsalis torquata","text":"Do que o bacurau-tesoura se alimenta principalmente?","diff":"media","src":"Birds of the World","options":[{"t":"Insetos capturados em voo","c":true},{"t":"Peixes","c":false},{"t":"Frutas","c":false},{"t":"Sementes","c":false}]},

  {"sci":"Aphantochroa cirrochloris","text":"A que família pertence o beija-flor-cinza?","diff":"facil","src":"Birds of the World","options":[{"t":"Trochilidae","c":true},{"t":"Caprimulgidae","c":false},{"t":"Ramphastidae","c":false},{"t":"Anatidae","c":false}]},
  {"sci":"Aphantochroa cirrochloris","text":"Os beija-flores, como o beija-flor-cinza, têm uma habilidade de voo singular. Qual?","diff":"media","src":"Animal Diversity Web","options":[{"t":"Voar para trás","c":true},{"t":"Planar por horas sem bater asas","c":false},{"t":"Voar em formação de V","c":false},{"t":"Mergulhar e nadar","c":false}]},

  {"sci":"Thalurania furcata","text":"A que família pertence o beija-flor-tesoura-verde?","diff":"facil","src":"Birds of the World","options":[{"t":"Trochilidae","c":true},{"t":"Falconidae","c":false},{"t":"Cervidae","c":false},{"t":"Boidae","c":false}]},
  {"sci":"Thalurania furcata","text":"Qual é a base da alimentação do beija-flor-tesoura-verde?","diff":"facil","src":"Animal Diversity Web","options":[{"t":"Néctar, complementado por pequenos insetos","c":true},{"t":"Folhas","c":false},{"t":"Peixes","c":false},{"t":"Sementes","c":false}]},

  {"sci":"Caracara plancus","text":"A que família pertence o carcará?","diff":"media","src":"Birds of the World","options":[{"t":"Falconidae","c":true},{"t":"Accipitridae","c":false},{"t":"Anatidae","c":false},{"t":"Cathartidae","c":false}]},
  {"sci":"Caracara plancus","text":"O carcará é mais bem descrito como:","diff":"facil","src":"Animal Diversity Web","options":[{"t":"Ave de rapina onívora e oportunista","c":true},{"t":"Ave aquática mergulhadora","c":false},{"t":"Pequeno pássaro insetívoro","c":false},{"t":"Ave corredora que não voa","c":false}]},
  {"sci":"Caracara plancus","text":"Entre estas aves de rapina, qual costuma ser a mais pesada?","diff":"media","src":"Birds of the World","options":[{"t":"Carcará","c":true},{"t":"Gavião-pernilongo","c":false},{"t":"Gavião-de-cauda-curta","c":false},{"t":"Gavião-gato","c":false}]},

  {"sci":"Blastocerus dichotomus","text":"A que família pertence o cervo-do-pantanal?","diff":"facil","src":"Animal Diversity Web","options":[{"t":"Cervidae","c":true},{"t":"Tapiridae","c":false},{"t":"Canidae","c":false},{"t":"Caviidae","c":false}]},
  {"sci":"Blastocerus dichotomus","text":"Qual é o maior cervídeo (veado) da América do Sul?","diff":"media","src":"Animal Diversity Web","options":[{"t":"Cervo-do-pantanal","c":true},{"t":"Bugio-ruivo","c":false},{"t":"Graxaim-do-campo","c":false},{"t":"Quati-de-cauda-anelada","c":false}]},
  {"sci":"Blastocerus dichotomus","text":"Segundo a IUCN, qual é o status de conservação do cervo-do-pantanal?","diff":"media","src":"IUCN Red List","options":[{"t":"Vulnerável","c":true},{"t":"Pouco preocupante","c":false},{"t":"Em perigo","c":false},{"t":"Extinta","c":false}]},
  {"sci":"Blastocerus dichotomus","text":"O cervo-do-pantanal está fortemente associado a que tipo de ambiente?","diff":"media","src":"IUCN Red List","options":[{"t":"Áreas alagadas e banhados","c":true},{"t":"Desertos","c":false},{"t":"Topos de montanha","c":false},{"t":"Cavernas","c":false}]},

  {"sci":"Didelphis albiventris","text":"O gambá-de-orelha-branca pertence a qual grupo de mamíferos?","diff":"media","src":"Animal Diversity Web","options":[{"t":"Marsupiais","c":true},{"t":"Roedores","c":false},{"t":"Primatas","c":false},{"t":"Carnívoros","c":false}]},
  {"sci":"Didelphis albiventris","text":"A que família pertence o gambá-de-orelha-branca?","diff":"dificil","src":"Animal Diversity Web","options":[{"t":"Didelphidae","c":true},{"t":"Procyonidae","c":false},{"t":"Mustelidae","c":false},{"t":"Caviidae","c":false}]},
  {"sci":"Didelphis albiventris","text":"Qual é a dieta do gambá-de-orelha-branca?","diff":"facil","src":"Animal Diversity Web","options":[{"t":"Onívora","c":true},{"t":"Apenas folhas","c":false},{"t":"Apenas peixes","c":false},{"t":"Apenas néctar","c":false}]},
  {"sci":"Didelphis albiventris","text":"Qual destes animais brasileiros é um marsupial?","diff":"media","src":"Animal Diversity Web","options":[{"t":"Gambá-de-orelha-branca","c":true},{"t":"Quati-de-cauda-anelada","c":false},{"t":"Capivara","c":false},{"t":"Jaguatirica","c":false}]},

  {"sci":"Busarellus nigricollis","text":"A que família pertencem os gaviões como o gavião-belo?","diff":"facil","src":"Birds of the World","options":[{"t":"Accipitridae","c":true},{"t":"Falconidae","c":false},{"t":"Anatidae","c":false},{"t":"Trochilidae","c":false}]},
  {"sci":"Busarellus nigricollis","text":"O gavião-belo é especializado em capturar:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Peixes","c":true},{"t":"Sementes","c":false},{"t":"Néctar","c":false},{"t":"Folhas","c":false}]},

  {"sci":"Buteo brachyurus","text":"A que família pertence o gavião-de-cauda-curta?","diff":"facil","src":"Birds of the World","options":[{"t":"Accipitridae","c":true},{"t":"Falconidae","c":false},{"t":"Cathartidae","c":false},{"t":"Anatidae","c":false}]},
  {"sci":"Buteo brachyurus","text":"Qual é o nome científico do gavião-de-cauda-curta?","diff":"dificil","src":"Birds of the World","options":[{"t":"Buteo brachyurus","c":true},{"t":"Buteogallus urubitinga","c":false},{"t":"Geranospiza caerulescens","c":false},{"t":"Busarellus nigricollis","c":false}]},

  {"sci":"Leptodon cayanensis","text":"Apesar do nome popular gavião-gato, esse animal é:","diff":"media","src":"Birds of the World","options":[{"t":"Uma ave de rapina","c":true},{"t":"Um felino","c":false},{"t":"Um marsupial","c":false},{"t":"Um réptil","c":false}]},
  {"sci":"Leptodon cayanensis","text":"A que família pertence o gavião-gato?","diff":"facil","src":"Birds of the World","options":[{"t":"Accipitridae","c":true},{"t":"Felidae","c":false},{"t":"Falconidae","c":false},{"t":"Procyonidae","c":false}]},

  {"sci":"Geranospiza caerulescens","text":"O nome pernilongo do gavião-pernilongo refere-se a quê?","diff":"media","src":"Birds of the World","options":[{"t":"Às suas pernas longas","c":true},{"t":"Ao bico longo","c":false},{"t":"À cauda longa","c":false},{"t":"Ao pescoço longo","c":false}]},
  {"sci":"Geranospiza caerulescens","text":"A que família pertence o gavião-pernilongo?","diff":"facil","src":"Birds of the World","options":[{"t":"Accipitridae","c":true},{"t":"Falconidae","c":false},{"t":"Ardeidae","c":false},{"t":"Anatidae","c":false}]},

  {"sci":"Buteogallus urubitinga","text":"A que família pertence o gavião-preto?","diff":"facil","src":"Birds of the World","options":[{"t":"Accipitridae","c":true},{"t":"Falconidae","c":false},{"t":"Cathartidae","c":false},{"t":"Rheidae","c":false}]},
  {"sci":"Buteogallus urubitinga","text":"Qual é o nome científico do gavião-preto?","diff":"dificil","src":"Birds of the World","options":[{"t":"Buteogallus urubitinga","c":true},{"t":"Buteo brachyurus","c":false},{"t":"Caracara plancus","c":false},{"t":"Leptodon cayanensis","c":false}]},

  {"sci":"Caiman yacare","text":"A que família pertence o jacaré-do-pantanal?","diff":"dificil","src":"Animal Diversity Web","options":[{"t":"Alligatoridae","c":true},{"t":"Crocodylidae","c":false},{"t":"Boidae","c":false},{"t":"Iguanidae","c":false}]},
  {"sci":"Caiman yacare","text":"O jacaré-do-pantanal pertence ao grupo dos jacarés (Alligatoridae), e não ao dos:","diff":"dificil","src":"Animal Diversity Web","options":[{"t":"Crocodilos verdadeiros","c":true},{"t":"Lagartos","c":false},{"t":"Serpentes","c":false},{"t":"Quelônios (tartarugas)","c":false}]},
  {"sci":"Caiman yacare","text":"Qual é o nome científico do jacaré-do-pantanal?","diff":"media","src":"IUCN Red List","options":[{"t":"Caiman yacare","c":true},{"t":"Caiman crocodilus","c":false},{"t":"Melanosuchus niger","c":false},{"t":"Alligator mississippiensis","c":false}]},
  {"sci":"Caiman yacare","text":"Qual destes é um réptil?","diff":"facil","src":"Animal Diversity Web","options":[{"t":"Jacaré-do-pantanal","c":true},{"t":"Ariranha","c":false},{"t":"Bugio-ruivo","c":false},{"t":"Tucano-toco","c":false}]},

  {"sci":"Leopardus pardalis","text":"A que família pertence a jaguatirica?","diff":"facil","src":"Animal Diversity Web","options":[{"t":"Felidae","c":true},{"t":"Canidae","c":false},{"t":"Mustelidae","c":false},{"t":"Procyonidae","c":false}]},
  {"sci":"Leopardus pardalis","text":"A jaguatirica e o gato-maracajá pertencem ao mesmo gênero. Qual?","diff":"extremo","src":"Animal Diversity Web","options":[{"t":"Leopardus","c":true},{"t":"Panthera","c":false},{"t":"Puma","c":false},{"t":"Felis","c":false}]},
  {"sci":"Leopardus pardalis","text":"Qual é o nome científico da jaguatirica?","diff":"media","src":"Animal Diversity Web","options":[{"t":"Leopardus pardalis","c":true},{"t":"Leopardus wiedii","c":false},{"t":"Panthera onca","c":false},{"t":"Puma concolor","c":false}]},

  {"sci":"Leopardus wiedii","text":"Qual destes felinos brasileiros é o menor em massa?","diff":"media","src":"Animal Diversity Web","options":[{"t":"Gato-maracajá","c":true},{"t":"Onça-pintada","c":false},{"t":"Puma","c":false},{"t":"Jaguatirica","c":false}]},

  {"sci":"Boa constrictor","text":"A que família pertence a jiboia?","diff":"media","src":"Animal Diversity Web","options":[{"t":"Boidae","c":true},{"t":"Viperidae","c":false},{"t":"Elapidae","c":false},{"t":"Colubridae","c":false}]},
  {"sci":"Boa constrictor","text":"Como a jiboia subjuga suas presas?","diff":"facil","src":"Animal Diversity Web","options":[{"t":"Por constrição, enrolando o corpo","c":true},{"t":"Com veneno potente","c":false},{"t":"Com choque elétrico","c":false},{"t":"Cuspindo veneno","c":false}]},
  {"sci":"Boa constrictor","text":"Sobre a jiboia, é correto afirmar que ela é:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Não peçonhenta","c":true},{"t":"Peçonhenta como a jararaca","c":false},{"t":"Peçonhenta como a coral","c":false},{"t":"Capaz de cuspir veneno","c":false}]},
  {"sci":"Boa constrictor","text":"Qual destes animais é uma serpente?","diff":"facil","src":"Animal Diversity Web","options":[{"t":"Jiboia","c":true},{"t":"Jacaré-do-pantanal","c":false},{"t":"Jaguatirica","c":false},{"t":"Sagui-de-tufos-pretos","c":false}]},

  {"sci":"Sapajus cay","text":"A que família pertence o macaco-prego-de-papo-amarelo?","diff":"media","src":"Animal Diversity Web","options":[{"t":"Cebidae","c":true},{"t":"Atelidae","c":false},{"t":"Callitrichidae","c":false},{"t":"Felidae","c":false}]},
  {"sci":"Sapajus cay","text":"Os macacos-prego (gênero Sapajus) são conhecidos por:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Usar ferramentas, como pedras para quebrar alimentos","c":true},{"t":"Hibernar no inverno","c":false},{"t":"Voar entre as árvores","c":false},{"t":"Viver embaixo da água","c":false}]},

  {"sci":"Dendrocygna autumnalis","text":"A que família pertencem as marrecas, como a marreca-cabocla?","diff":"facil","src":"Birds of the World","options":[{"t":"Anatidae","c":true},{"t":"Rheidae","c":false},{"t":"Trochilidae","c":false},{"t":"Accipitridae","c":false}]},
  {"sci":"Dendrocygna autumnalis","text":"A marreca-cabocla é uma ave de que tipo?","diff":"facil","src":"Birds of the World","options":[{"t":"Aquática","c":true},{"t":"De rapina","c":false},{"t":"Corredora terrestre","c":false},{"t":"Noturna insetívora","c":false}]},
  {"sci":"Dendrocygna autumnalis","text":"Entre estas marrecas, qual é a maior?","diff":"media","src":"Birds of the World","options":[{"t":"Marreca-cabocla","c":true},{"t":"Marreca-cricri","c":false},{"t":"Marreca-de-coleira","c":false},{"t":"Marreca-rabo-de-espinho","c":false}]},

  {"sci":"Anas platalea","text":"A marreca-colhereira (Anas platalea) recebe esse nome por causa de:","diff":"media","src":"Birds of the World","options":[{"t":"Seu bico largo em forma de colher","c":true},{"t":"Sua cauda pontuda","c":false},{"t":"Suas pernas muito longas","c":false},{"t":"Sua crista colorida","c":false}]},

  {"sci":"Phaethornis eurynome","text":"A que família pertence o rabo-branco-de-garganta-rajada?","diff":"facil","src":"Birds of the World","options":[{"t":"Trochilidae","c":true},{"t":"Caprimulgidae","c":false},{"t":"Anatidae","c":false},{"t":"Ramphastidae","c":false}]},
  {"sci":"Phaethornis eurynome","text":"Em qual bioma vive o rabo-branco-de-garganta-rajada?","diff":"media","src":"IUCN Red List","options":[{"t":"Mata Atlântica","c":true},{"t":"Pampa","c":false},{"t":"Caatinga","c":false},{"t":"Pantanal","c":false}]},
  {"sci":"Phaethornis eurynome","text":"O rabo-branco-de-garganta-rajada é um tipo de:","diff":"facil","src":"Birds of the World","options":[{"t":"Beija-flor","c":true},{"t":"Pato","c":false},{"t":"Gavião","c":false},{"t":"Tucano","c":false}]},

  {"sci":"Callithrix jacchus","text":"A que família pertencem os saguis?","diff":"media","src":"Animal Diversity Web","options":[{"t":"Callitrichidae","c":true},{"t":"Cebidae","c":false},{"t":"Atelidae","c":false},{"t":"Didelphidae","c":false}]},
  {"sci":"Callithrix jacchus","text":"Os saguis têm um hábito alimentar peculiar. Qual?","diff":"media","src":"Animal Diversity Web","options":[{"t":"Roem troncos para consumir a goma (exsudato) das árvores","c":true},{"t":"Caçam peixes em rios","c":false},{"t":"Filtram plâncton","c":false},{"t":"Alimentam-se apenas de carne","c":false}]},
  {"sci":"Callithrix jacchus","text":"Qual é o nome científico do sagui-de-tufos-brancos?","diff":"extremo","src":"Animal Diversity Web","options":[{"t":"Callithrix jacchus","c":true},{"t":"Callithrix penicillata","c":false},{"t":"Saguinus midas","c":false},{"t":"Leontopithecus rosalia","c":false}]},

  {"sci":"Callithrix penicillata","text":"O sagui-de-tufos-pretos (Callithrix penicillata) distingue-se do sagui-de-tufos-brancos principalmente por:","diff":"extremo","src":"Animal Diversity Web","options":[{"t":"A cor dos tufos auriculares","c":true},{"t":"O número de dedos","c":false},{"t":"Possuir asas","c":false},{"t":"Viver no mar","c":false}]},

  {"sci":"Ramphastos toco","text":"A que família pertence o tucano-toco?","diff":"facil","src":"Birds of the World","options":[{"t":"Ramphastidae","c":true},{"t":"Trochilidae","c":false},{"t":"Accipitridae","c":false},{"t":"Anatidae","c":false}]},
  {"sci":"Ramphastos toco","text":"Qual é o maior tucano do mundo?","diff":"facil","src":"Birds of the World","options":[{"t":"Tucano-toco","c":true},{"t":"Beija-flor-cinza","c":false},{"t":"Carcará","c":false},{"t":"Bacurau-tesoura","c":false}]},
  {"sci":"Ramphastos toco","text":"Além de manusear alimentos, o grande bico do tucano-toco também atua em:","diff":"media","src":"Birds of the World","options":[{"t":"Regular a temperatura do corpo","c":true},{"t":"Produzir veneno","c":false},{"t":"Cavar tocas no chão","c":false},{"t":"Filtrar água","c":false}]},
  {"sci":"Ramphastos toco","text":"Qual é o nome científico do tucano-toco?","diff":"media","src":"Birds of the World","options":[{"t":"Ramphastos toco","c":true},{"t":"Ramphastos dicolorus","c":false},{"t":"Pteroglossus aracari","c":false},{"t":"Rhea americana","c":false}]},

  {"sci":"Rhea americana","text":"Qual destas é uma ave corredora, que não voa?","diff":"facil","src":"Birds of the World","options":[{"t":"Ema","c":true},{"t":"Carcará","c":false},{"t":"Tucano-toco","c":false},{"t":"Marreca-cabocla","c":false}]},
  {"sci":"Rhea americana","text":"A que família pertence a ema?","diff":"media","src":"Birds of the World","options":[{"t":"Rheidae","c":true},{"t":"Anatidae","c":false},{"t":"Accipitridae","c":false},{"t":"Ramphastidae","c":false}]}
  ]$json$::jsonb;
begin
  for q in select value from jsonb_array_elements(qs) loop
    select id into sid from species where scientific_name = q->>'sci';
    insert into quiz_questions (species_id, question_text, difficulty, source, time_limit_seconds, is_active)
      values (sid, q->>'text', q->>'diff', q->>'src', 20, true)
      returning id into qid;
    for opt in select value from jsonb_array_elements(q->'options') loop
      insert into quiz_answer_options (question_id, option_text, is_correct)
        values (qid, opt->>'t', (opt->>'c')::boolean);
    end loop;
  end loop;
end $$;;
