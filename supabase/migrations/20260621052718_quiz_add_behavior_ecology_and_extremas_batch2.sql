do $$
declare
  q jsonb; qid uuid; sid uuid; opt jsonb;
  qs jsonb := $json$[
  {"sci":"Tapirus terrestris","text":"Diante de um predador, a anta frequentemente:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Mergulha e foge pela água","c":true},{"t":"Finge-se de morta","c":false},{"t":"Sobe em árvores altas","c":false},{"t":"Voa para longe","c":false}]},
  {"sci":"Tapirus terrestris","text":"A anta possui, no focinho, uma estrutura móvel e preênsil chamada:","diff":"dificil","src":"Animal Diversity Web","options":[{"t":"Probóscide (uma pequena tromba)","c":true},{"t":"Tromba longa com presas, como a do elefante","c":false},{"t":"Bico córneo","c":false},{"t":"Guelras","c":false}]},
  {"sci":"Tapirus terrestris","text":"Os filhotes de anta apresentam, na pelagem, um padrão de:","diff":"dificil","src":"Animal Diversity Web","options":[{"t":"Listras e manchas claras, que servem de camuflagem","c":true},{"t":"Pelagem totalmente preta","c":false},{"t":"Penas coloridas","c":false},{"t":"Escamas","c":false}]},

  {"sci":"Pteronura brasiliensis","text":"Quanto ao comportamento social, a ariranha:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Vive em grupos familiares coesos","c":true},{"t":"É estritamente solitária","c":false},{"t":"Forma casais apenas no inverno","c":false},{"t":"Vive em bandos de centenas de indivíduos","c":false}]},
  {"sci":"Pteronura brasiliensis","text":"No ecossistema aquático, a ariranha atua como:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Predador de topo, alimentando-se de peixes","c":true},{"t":"Filtradora de plâncton","c":false},{"t":"Herbívora aquática","c":false},{"t":"Decompositora de matéria orgânica","c":false}]},
  {"sci":"Pteronura brasiliensis","text":"Quanto ao período de atividade, a ariranha é principalmente:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Diurna","c":true},{"t":"Noturna","c":false},{"t":"Subterrânea","c":false},{"t":"Ativa apenas na lua cheia","c":false}]},

  {"sci":"Alouatta guariba clamitans","text":"O bugio-ruivo usa a cauda preênsil como:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Um quinto membro, para se segurar nos galhos","c":true},{"t":"Arma de defesa, com ferrão","c":false},{"t":"Único órgão de armazenamento de gordura","c":false},{"t":"Remo para nadar","c":false}]},
  {"sci":"Alouatta guariba clamitans","text":"Os bugios são muito sensíveis a uma doença e funcionam como sentinelas dela na natureza. Qual?","diff":"extremo","src":"Literatura veterinária e de saúde única","options":[{"t":"Febre amarela","c":true},{"t":"Raiva","c":false},{"t":"Tuberculose","c":false},{"t":"Leptospirose","c":false}]},

  {"sci":"Hydrochoerus hydrochaeris","text":"A capivara pratica a coprofagia (reingestão das próprias fezes) sobretudo para:","diff":"extremo","src":"Animal Diversity Web","options":[{"t":"Reaproveitar nutrientes e a flora que digere a celulose","c":true},{"t":"Marcar território","c":false},{"t":"Eliminar parasitas","c":false},{"t":"Resfriar o corpo","c":false}]},
  {"sci":"Hydrochoerus hydrochaeris","text":"A capivara tem importância epidemiológica por hospedar carrapatos do gênero Amblyomma ligados a qual doença?","diff":"extremo","src":"Literatura veterinária e de saúde única","options":[{"t":"Febre maculosa brasileira","c":true},{"t":"Dengue","c":false},{"t":"Malária","c":false},{"t":"Esquistossomose","c":false}]},
  {"sci":"Hydrochoerus hydrochaeris","text":"A capivara costuma viver:","diff":"facil","src":"Animal Diversity Web","options":[{"t":"Em grupos, sempre perto da água","c":true},{"t":"Sempre sozinha","c":false},{"t":"Em tocas subterrâneas profundas","c":false},{"t":"No alto das árvores","c":false}]},
  {"sci":"Hydrochoerus hydrochaeris","text":"No Pantanal e em outros biomas, a capivara é presa importante de qual predador de topo?","diff":"media","src":"Animal Diversity Web","options":[{"t":"Onça-pintada","c":true},{"t":"Beija-flor-cinza","c":false},{"t":"Tucano-toco","c":false},{"t":"Marreca-cricri","c":false}]},

  {"sci":"Chrysocyon brachyurus","text":"Um item central da dieta do lobo-guará, cujas sementes ele dispersa, é a fruta de qual planta?","diff":"dificil","src":"Literatura zoológica","options":[{"t":"Lobeira (Solanum lycocarpum)","c":true},{"t":"Cacaueiro","c":false},{"t":"Pequizeiro","c":false},{"t":"Buritizeiro","c":false}]},
  {"sci":"Chrysocyon brachyurus","text":"Quanto ao hábito, o lobo-guará é:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Solitário e de atividade crepuscular e noturna","c":true},{"t":"Caçador em matilhas","c":false},{"t":"Aquático","c":false},{"t":"Hibernante","c":false}]},

  {"sci":"Panthera onca","text":"A onça-pintada se diferencia de outros grandes felinos no modo de matar a presa. Como?","diff":"extremo","src":"Literatura zoológica","options":[{"t":"Perfura o crânio da presa com a mordida","c":true},{"t":"Estrangula sempre pela garganta, como o leão","c":false},{"t":"Inocula veneno","c":false},{"t":"Derruba a presa de penhascos","c":false}]},
  {"sci":"Panthera onca","text":"Sobre a relação da onça-pintada com a água:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Nada bem e caça também na água","c":true},{"t":"Evita totalmente a água","c":false},{"t":"Vive no mar","c":false},{"t":"Não sabe nadar","c":false}]},
  {"sci":"Panthera onca","text":"As rosetas da onça-pintada diferem das do leopardo-africano por:","diff":"dificil","src":"Literatura zoológica","options":[{"t":"Geralmente terem manchas (pontos) no interior","c":true},{"t":"Serem listras","c":false},{"t":"Não existirem","c":false},{"t":"Serem azuladas","c":false}]},
  {"sci":"Panthera onca","text":"A diferença anatômica que permite à onça-pintada rugir, mas não ao puma, está em qual estrutura?","diff":"extremo","src":"Literatura zoológica","options":[{"t":"O aparato hioide (osso hioide)","c":true},{"t":"A coluna vertebral","c":false},{"t":"A cauda","c":false},{"t":"As garras","c":false}]},

  {"sci":"Puma concolor","text":"Diferente da onça-pintada, o puma não consegue:","diff":"dificil","src":"Literatura zoológica","options":[{"t":"Rugir (em vez disso, ele ronrona)","c":true},{"t":"Correr","c":false},{"t":"Subir em árvores","c":false},{"t":"Enxergar à noite","c":false}]},
  {"sci":"Puma concolor","text":"O puma chama atenção por ter:","diff":"media","src":"Animal Diversity Web","options":[{"t":"A maior distribuição entre os mamíferos terrestres selvagens das Américas","c":true},{"t":"Distribuição restrita a uma pequena área da Amazônia","c":false},{"t":"Distribuição apenas no litoral","c":false},{"t":"Vida exclusivamente aquática","c":false}]},

  {"sci":"Leopardus wiedii","text":"O gato-maracajá é um felino especialmente adaptado a:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Viver nas árvores (hábito arborícola)","c":true},{"t":"Viver no subsolo","c":false},{"t":"Viver no mar","c":false},{"t":"Correr longas distâncias em campo aberto","c":false}]},

  {"sci":"Leopardus pardalis","text":"A jaguatirica caça sobretudo:","diff":"media","src":"Animal Diversity Web","options":[{"t":"À noite, com hábito noturno e crepuscular","c":true},{"t":"Ao meio-dia","c":false},{"t":"Debaixo da água","c":false},{"t":"Em pleno voo","c":false}]},
  {"sci":"Leopardus pardalis","text":"A base da dieta da jaguatirica são:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Pequenos vertebrados, como roedores, aves e répteis","c":true},{"t":"Frutas","c":false},{"t":"Folhas","c":false},{"t":"Néctar","c":false}]},

  {"sci":"Nasua nasua","text":"Nos quatis, os bandos são formados principalmente por:","diff":"dificil","src":"Animal Diversity Web","options":[{"t":"Fêmeas e filhotes, enquanto os machos adultos vivem sós","c":true},{"t":"Apenas machos adultos","c":false},{"t":"Casais fixos por toda a vida","c":false},{"t":"Milhares de indivíduos sem parentesco","c":false}]},
  {"sci":"Nasua nasua","text":"Quanto ao período de atividade, o quati é:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Diurno","c":true},{"t":"Estritamente noturno","c":false},{"t":"Ativo só na lua cheia","c":false},{"t":"Hibernante","c":false}]},

  {"sci":"Didelphis albiventris","text":"Uma estratégia de defesa típica do gambá é:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Fingir-se de morto (tanatose)","c":true},{"t":"Soltar tinta","c":false},{"t":"Mudar a cor da pele","c":false},{"t":"Planar entre árvores","c":false}]},
  {"sci":"Didelphis albiventris","text":"O gambá (Didelphis) é notável por ter, no sangue, fatores capazes de neutralizar:","diff":"extremo","src":"Literatura parasitológica e toxinológica","options":[{"t":"O veneno de serpentes","c":true},{"t":"Antibióticos","c":false},{"t":"Metais pesados","c":false},{"t":"Raios ultravioleta","c":false}]},
  {"sci":"Didelphis albiventris","text":"O gambá é um importante reservatório silvestre de qual parasito causador de doença humana?","diff":"extremo","src":"Literatura parasitológica","options":[{"t":"Trypanosoma cruzi, da doença de Chagas","c":true},{"t":"Plasmodium, da malária","c":false},{"t":"Schistosoma mansoni, da esquistossomose","c":false},{"t":"Wuchereria bancrofti, da filariose","c":false}]},

  {"sci":"Blastocerus dichotomus","text":"O cervo-do-pantanal alimenta-se bastante de:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Plantas aquáticas e de áreas alagadas","c":true},{"t":"Carne","c":false},{"t":"Peixes","c":false},{"t":"Néctar","c":false}]},
  {"sci":"Blastocerus dichotomus","text":"Uma adaptação do cervo-do-pantanal para o ambiente alagado é:","diff":"dificil","src":"Literatura zoológica","options":[{"t":"Membranas entre os cascos, que ajudam a andar no charco","c":true},{"t":"Nadadeiras no lugar das patas","c":false},{"t":"Guelras","c":false},{"t":"Cascos com ventosas","c":false}]},

  {"sci":"Callithrix jacchus","text":"Os saguis têm uma adaptação incomum entre os primatas nas mãos e pés. Qual?","diff":"extremo","src":"Animal Diversity Web","options":[{"t":"Unhas em forma de garra, para se prender a troncos","c":true},{"t":"Ausência de polegares","c":false},{"t":"Membranas para planar","c":false},{"t":"Ventosas nos dedos","c":false}]},
  {"sci":"Callithrix jacchus","text":"Os incisivos inferiores dos saguis são adaptados para:","diff":"dificil","src":"Animal Diversity Web","options":[{"t":"Roer a casca das árvores e estimular a saída de goma","c":true},{"t":"Triturar ossos","c":false},{"t":"Filtrar água","c":false},{"t":"Cortar carne","c":false}]},
  {"sci":"Callithrix penicillata","text":"Entre os saguis, é comum o nascimento de:","diff":"dificil","src":"Animal Diversity Web","options":[{"t":"Gêmeos, com cuidado cooperativo do grupo","c":true},{"t":"Dezenas de filhotes por ninhada","c":false},{"t":"Filhotes que já nascem adultos","c":false},{"t":"Ovos","c":false}]},

  {"sci":"Sapajus cay","text":"O uso de pedras como ferramenta pelos macacos-prego serve sobretudo para:","diff":"dificil","src":"Animal Diversity Web","options":[{"t":"Quebrar alimentos duros, como cocos e sementes","c":true},{"t":"Acender fogo","c":false},{"t":"Cavar túneis","c":false},{"t":"Pescar com anzol","c":false}]},

  {"sci":"Rhea americana","text":"Na ema, quem incuba os ovos e cuida dos filhotes é:","diff":"dificil","src":"Birds of the World","options":[{"t":"O macho","c":true},{"t":"A fêmea sozinha","c":false},{"t":"Ambos por igual","c":false},{"t":"Nenhum; os ovos ficam ao léu","c":false}]},
  {"sci":"Rhea americana","text":"A ema é uma ave de dieta:","diff":"media","src":"Birds of the World","options":[{"t":"Onívora, com plantas e pequenos animais","c":true},{"t":"Exclusivamente carnívora","c":false},{"t":"Exclusivamente de néctar","c":false},{"t":"Hematófaga","c":false}]},

  {"sci":"Ramphastos toco","text":"No Cerrado, o tucano-toco tem papel ecológico de:","diff":"media","src":"Birds of the World","options":[{"t":"Dispersor de sementes (frugívoro)","c":true},{"t":"Polinizador noturno","c":false},{"t":"Predador de topo","c":false},{"t":"Filtrador de água","c":false}]},
  {"sci":"Ramphastos toco","text":"Além de frutas, o tucano-toco pode, oportunisticamente, comer:","diff":"dificil","src":"Birds of the World","options":[{"t":"Ovos e filhotes de outras aves","c":true},{"t":"Apenas folhas","c":false},{"t":"Peixes em alto-mar","c":false},{"t":"Sangue","c":false}]},

  {"sci":"Aphantochroa cirrochloris","text":"Para economizar energia em noites frias, os beija-flores podem entrar em:","diff":"dificil","src":"Animal Diversity Web","options":[{"t":"Torpor, com queda controlada do metabolismo","c":true},{"t":"Hibernação de vários meses","c":false},{"t":"Muda total das penas","c":false},{"t":"Migração subterrânea","c":false}]},
  {"sci":"Aphantochroa cirrochloris","text":"Ecologicamente, os beija-flores são importantes sobretudo como:","diff":"facil","src":"Birds of the World","options":[{"t":"Polinizadores","c":true},{"t":"Decompositores","c":false},{"t":"Predadores de topo","c":false},{"t":"Dispersores de grandes sementes","c":false}]},
  {"sci":"Thalurania furcata","text":"Os beija-flores precisam se alimentar com muita frequência porque têm:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Metabolismo muito acelerado","c":true},{"t":"Um estômago que não digere alimentos","c":false},{"t":"Voo muito lento","c":false},{"t":"Capacidade de passar semanas sem comer","c":false}]},

  {"sci":"Hydropsalis torquata","text":"Para nidificar, o bacurau geralmente:","diff":"dificil","src":"Birds of the World","options":[{"t":"Põe os ovos diretamente no chão, sem ninho elaborado","c":true},{"t":"Constrói ninhos pendurados","c":false},{"t":"Cava tocas profundas","c":false},{"t":"Usa cupinzeiros ativos","c":false}]},
  {"sci":"Hydropsalis torquata","text":"Durante o dia, o bacurau se protege principalmente por meio de:","diff":"media","src":"Birds of the World","options":[{"t":"Camuflagem, com plumagem que imita o solo e a folhagem seca","c":true},{"t":"Veneno","c":false},{"t":"Uma concha protetora","c":false},{"t":"Formar grandes bandos barulhentos","c":false}]},

  {"sci":"Busarellus nigricollis","text":"Para capturar peixes, o gavião-belo tem patas com:","diff":"dificil","src":"Birds of the World","options":[{"t":"Superfície áspera, que ajuda a segurar presas escorregadias","c":true},{"t":"Membranas de pato","c":false},{"t":"Ventosas","c":false},{"t":"Garras que não se movem","c":false}]},

  {"sci":"Geranospiza caerulescens","text":"O gavião-pernilongo usa suas pernas longas e articuladas para:","diff":"dificil","src":"Birds of the World","options":[{"t":"Alcançar presas escondidas em ocos e bromélias","c":true},{"t":"Nadar","c":false},{"t":"Escavar o solo","c":false},{"t":"Quebrar sementes","c":false}]},

  {"sci":"Caracara plancus","text":"Um comportamento típico do carcará é:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Andar no chão à procura de alimento, inclusive carniça","c":true},{"t":"Mergulhar no mar atrás de peixes","c":false},{"t":"Caçar apenas à noite","c":false},{"t":"Filtrar lama em busca de plâncton","c":false}]},

  {"sci":"Caiman yacare","text":"Por ser ectotérmico, o jacaré-do-pantanal regula sua temperatura:","diff":"dificil","src":"Animal Diversity Web","options":[{"t":"Tomando sol e se abrigando na água ou na sombra","c":true},{"t":"Produzindo calor pelo tremor, como as aves","c":false},{"t":"Suando","c":false},{"t":"Hibernando o ano inteiro","c":false}]},
  {"sci":"Caiman yacare","text":"Sobre o cuidado parental no jacaré-do-pantanal:","diff":"dificil","src":"Animal Diversity Web","options":[{"t":"A fêmea protege o ninho e os filhotes recém-nascidos","c":true},{"t":"Não há qualquer cuidado com a prole","c":false},{"t":"O macho choca os ovos no próprio corpo","c":false},{"t":"Os filhotes já nascem adultos","c":false}]},

  {"sci":"Boa constrictor","text":"Quanto à reprodução, a jiboia:","diff":"extremo","src":"Literatura zoológica (herpetologia)","options":[{"t":"Dá à luz filhotes vivos, sem botar ovos","c":true},{"t":"Põe ovos e os choca como as galinhas","c":false},{"t":"Reproduz-se por divisão do corpo","c":false},{"t":"Bota ovos na água, como os peixes","c":false}]},
  {"sci":"Boa constrictor","text":"A jiboia caça principalmente:","diff":"media","src":"Animal Diversity Web","options":[{"t":"De emboscada, esperando a presa se aproximar","c":true},{"t":"Perseguindo presas por quilômetros em alta velocidade","c":false},{"t":"Em bandos coordenados","c":false},{"t":"Filtrando a água","c":false}]},

  {"sci":"Dendrocygna autumnalis","text":"A marreca-cabocla tem um hábito incomum entre os patos. Qual?","diff":"dificil","src":"Birds of the World","options":[{"t":"Pousa em árvores e costuma nidificar em ocos","c":true},{"t":"Vive no mar aberto","c":false},{"t":"Não sabe nadar","c":false},{"t":"Mergulha a grandes profundidades, como o pinguim","c":false}]},
  {"sci":"Anas versicolor","text":"A maioria das marrecas se alimenta:","diff":"media","src":"Birds of the World","options":[{"t":"Filtrando ou pastando vegetação e invertebrados na água","c":true},{"t":"Caçando mamíferos","c":false},{"t":"De néctar de flores","c":false},{"t":"De sangue","c":false}]},

  {"sci":"Lycalopex gymnocercus","text":"A dieta do graxaim-do-campo é tipicamente:","diff":"media","src":"Animal Diversity Web","options":[{"t":"Onívora e oportunista","c":true},{"t":"Apenas de capim","c":false},{"t":"Apenas de peixes","c":false},{"t":"Apenas de néctar","c":false}]}
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
