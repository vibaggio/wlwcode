# WildLens — Auditoria técnica, de segurança, arquitetura e funcionalidade

**Data da auditoria:** 6 de outubro de 2026  
**Escopo:** arquivo `wlw.zip` + estado remoto atual do projeto Supabase vinculado ao código  
**Objetivo:** produzir uma avaliação que possa ser usada por outra IA como especificação operacional para correções, endurecimento, testes e evolução do sistema.

---

## 1. Veredito executivo

O sistema está **funcional como protótipo/alpha jogável**, e a arquitetura tem uma decisão conceitualmente boa: a maior parte das regras que alteram estado importante — cartas, moeda, pacotes, partidas, mercado, trocas, conquistas e permissões — foi colocada no PostgreSQL/Supabase em RPCs, em vez de confiar no JavaScript do navegador.

Entretanto, **eu não homologaria o estado atual como “seguro” nem como economicamente íntegro para exposição pública ampla**. Existem falhas de lógica que um cliente malicioso pode explorar sem necessidade de quebrar RLS:

1. **Quiz com exploração de recompensa.** O RPC público aceita quantidade arbitrária de questões; a interface manda 5, mas o servidor não impõe esse limite. Como a recompensa é proporcional ao número de acertos, isso cria potencial de farm de moeda.
2. **Quiz com revelação + reenvio da mesma resposta.** A primeira resposta pode fazer o servidor devolver a opção correta; a mesma questão pode ser respondida novamente; a pontuação final usa o estado final da resposta. A sequência “responder errado → obter resposta correta → reenviar correta → finalizar” pode transformar o mecanismo de correção em bypass da finalidade educacional.
3. **Consentimento legal fail-open no frontend.** Quando o RPC de status jurídico falha, o `ConsentGate` assume `accepted=true`. Em falha de rede/backend, a barreira deixa de existir.
4. **Gate de NDA também pode ser contornado por falha de carregamento do perfil.** O `Main` só bloqueia a interface quando `profile` existe e o campo não está aceito; se a leitura do perfil falha e permanece `null`, a lógica não força estado de erro.
5. **Cinco views `SECURITY DEFINER` foram sinalizadas pelo Security Advisor.** O banco está protegido em muitos pontos por RLS, mas essas views executam com privilégios do proprietário, não do chamador, e devem ser revistas deliberadamente.
6. **Arquitetura de entrega não é reproduzível.** O ZIP não contém o schema/base inicial nem `seed.sql`, embora `config.toml` aponte para ele. As 69 migrations são incrementais e partem de um banco previamente existente. Portanto, o pacote não constitui hoje um “repositório que reconstrói o projeto do zero”.
7. **Fonte, bundle e infraestrutura estão excessivamente concentrados.** Há uma SPA com fonte JSX inteira em um único HTML privado, um bundle minificado separado e praticamente nenhuma infraestrutura de build/teste. Isso funciona, mas aumenta muito o risco de divergência e dificulta auditoria automatizada.

### Classificação geral

| Dimensão | Avaliação | Interpretação |
|---|---:|---|
| Jogabilidade do núcleo | **7/10** | Fluxos principais existem e a maior parte das regras está no servidor. |
| Integridade transacional | **7/10** | Compras, mercado, trocas e pacote gratuito têm boas travas; há lacunas em check-in e limites concorrentes. |
| Segurança de dados/RLS | **7/10** | RLS está habilitado em todas as 46 tabelas públicas; acesso anônimo por RPC está bloqueado. |
| Segurança de lógica de jogo | **4/10** | O quiz tem vulnerabilidade econômica/anti-cheat relevante. |
| Segurança de views/RPCs | **5/10** | Muitos `SECURITY DEFINER`; cinco views são alertadas e a API tem superfície ampla. |
| Manutenibilidade | **3/10** | Monólito de ~5 mil linhas de fonte, bundle manual e ausência de testes/build. |
| Reprodutibilidade | **2/10** | Falta baseline/schema e falta seed do banco. Configuração aponta para projeto diferente. |
| Observabilidade | **3/10** | Muitos erros são engolidos silenciosamente no frontend; não há camada clara de logging/telemetria. |
| Pronto para produção pública | **4/10** | **Ainda não.** Recomendação: corrigir P0/P1 antes de ampliar o público. |

---

# 2. O que foi realmente auditado

## 2.1 Arquivo recebido

O ZIP contém **83 arquivos reais e 3 entradas de diretório**, totalizando 86 entradas no ZIP.

Composição:

- `9` arquivos em `supabase/.temp/`.
- `5` arquivos de aplicação/configuração na raiz de `supabase/`.
- `69` migrations SQL.
- Não há `.git`, `.github`, workflow de CI, `package.json`, lockfile, `vite.config.*`, `tsconfig.*`, testes automatizados ou pipeline de build no arquivo recebido.

Também foi criado, durante a própria análise, um arquivo de trabalho `app_source_extracted.jsx` no diretório de auditoria; **esse arquivo NÃO fazia parte do ZIP original** e não deve ser tratado como source-of-truth do projeto.

## 2.2 Estado remoto do Supabase

O projeto remoto associado ao identificador presente no pacote está ativo e saudável. A auditoria remota encontrou:

- PostgreSQL 17.6.1.155.
- 46 tabelas no schema `public`.
- 8 views no schema `public`.
- 0 materialized views.
- 69 migrations do pacote também aparecem aplicadas no projeto remoto.
- 0 Edge Functions.
- Todas as 46 tabelas públicas estão com RLS habilitado.
- 0 funções RPC `app_*` chamadas pelo frontend estão ausentes: os 71 nomes encontrados no código possuem implementação remota com assinatura compatível.
- Nenhuma função pública exposta ao cliente aceita execução pelo papel `anon`; as funções `app_*` estão disponíveis apenas para `authenticated`.

### Snapshot atual de dados

Os números abaixo são leituras diretas do banco no momento da auditoria, não estimativas de `pg_class.reltuples`:

| Entidade | Registros |
|---|---:|
| `profiles` | 9 |
| `species` | 55 |
| `card_instances` | 801 |
| `card_instance_attributes` | 2.403 |
| `card_transactions` | 2.423 |
| `photos` | 72 |
| `quiz_questions` ativas | 148 |
| `quiz_answer_options` | 592 |
| `ranked_matches` | 219 |
| `ranked_teams` atuais | 0 |
| `pack_openings` | 170 |
| `currency_ledger` | 277 |

O fato de haver **219 partidas ranqueadas históricas e 0 `ranked_teams` atuais** merece uma decisão explícita: pode ser uma limpeza deliberada de alpha, mas significa que, no snapshot auditado, a ranqueada não tem jogadores ativos suficientes para funcionar como ranking corrente.

---

# 3. Arquitetura atual

## 3.1 Modelo lógico

A arquitetura observada é:

```text
                    ┌─────────────────────────┐
                    │  index.html / browser   │
                    │  React UMD + JSX bundle │
                    └────────────┬────────────┘
                                 │
                                 │ supabase-js / REST RPC
                                 ▼
                    ┌─────────────────────────┐
                    │      Supabase Data API  │
                    │  authenticated + RLS    │
                    └────────────┬────────────┘
                                 │
              ┌──────────────────┴──────────────────┐
              │                                     │
              ▼                                     ▼
    ┌──────────────────────┐             ┌──────────────────────┐
    │ public tables/views  │             │ PostgreSQL RPC layer │
    │ catálogo + leituras  │             │ regras/mutações       │
    └──────────────────────┘             └───────────┬──────────┘
                                                    │
                                                    ▼
                              ┌───────────────────────────────────┐
                              │ estado persistente                │
                              │ cartas / moeda / quiz / partidas │
                              │ mercado / trades / família       │
                              └───────────────────────────────────┘
```

### O que é bom nesta arquitetura

A divisão “**navegador mostra e solicita; banco decide e grava**” é a direção correta para um jogo com economia interna. O cliente não deve ser a autoridade sobre propriedade da carta, saldo, recompensa ou autorização de compra; o projeto já segue isso em grande parte.

As operações de maior risco usam `FOR UPDATE`, locks de perfil ou advisory locks em vários pontos. Isso é particularmente bom em:

- compra de pacote;
- compra de anúncio do mercado;
- resposta de troca;
- resgate de conquista;
- resgate de boas-vindas;
- abertura do pacote gratuito.

### O que está ruim estruturalmente

A camada de aplicação é um **monólito React de arquivo único**, incorporando login, consentimento, coleção, cartas, quiz, mercado, trocas, ranqueada, perfil, família, loja, admin e conteúdo institucional. Isso torna a aplicação difícil de testar por domínio.

Em paralelo, existe um HTML privado que contém a fonte JSX inteira, enquanto a página pública roda `app.min.js`. Como ambos são artefatos diferentes, qualquer ajuste feito na fonte precisa gerar novamente o bundle; não existe mecanismo visível no pacote que imponha isso.

---

# 4. Auditoria do frontend

## 4.1 `supabase/index.html`

**Função:** shell estático da aplicação.

Carrega:

- Google Fonts;
- React 18.3.1 UMD;
- ReactDOM 18.3.1 UMD;
- `@supabase/supabase-js@2` via CDN com versão flutuante;
- `app.min.js` local.

### Pontos positivos

- Simples.
- Pouquíssima superfície HTML.
- React e ReactDOM estão pinados em 18.3.1.

### Problemas

1. `@supabase/supabase-js@2` não está pinado a uma versão exata.
2. Os scripts CDN não têm Subresource Integrity (SRI).
3. Não há CSP visível no HTML nem outra política equivalente declarada no pacote.
4. Não existe mecanismo de cache-busting/hash do bundle.
5. O arquivo depende de rede para bibliotecas externas antes de a aplicação iniciar.

### Ajuste recomendado

Migrar para build determinístico com dependências versionadas no lockfile. Se for mantida a estratégia CDN, pelo menos piná-la a uma versão exata, adicionar SRI quando possível e definir uma política CSP deliberada.

---

## 4.2 `supabase/styles.css`

**Tamanho:** ~28 KB, 355 linhas.

O CSS tem um design system razoavelmente consistente, com cerca de 55 custom properties, cinco animações e uma media query explícita.

### Pontos positivos

- Tokens de tipografia, espaçamento, radius e sombras.
- Uso consistente de variáveis CSS.
- Estrutura visual suficientemente madura para um projeto alpha.
- Há suporte explícito a responsividade.

### Pontos a melhorar

A questão principal não é estética, mas qualidade de software:

- como não existe pipeline de CSS/build, nenhuma verificação automatizada de regressão é possível;
- uma única media query é pouca evidência de teste real de tamanhos distintos;
- acessibilidade deve ser testada por interação real, não apenas pela quantidade de atributos no JSX.

A auditoria encontrou 135 `<button>`, 25 `<input>`, 10 `<img>`, apenas alguns atributos ARIA e somente um handler de teclado explícito. Isso não significa automaticamente baixa acessibilidade, mas justifica testes de teclado, foco, leitor de tela e contraste.

---

## 4.3 `supabase/app.min.js`

**Tamanho:** ~263 KB, uma única linha.

### Verificações realizadas

- `node --check app.min.js`: **passou**.
- O conjunto de 71 chamadas `app_*` esperado pelo frontend bate com as funções remotas encontradas no banco.
- Não foram encontrados `eval`, `new Function`, `innerHTML`, `dangerouslySetInnerHTML` ou `fetch` direto no código-fonte extraído.

### Problema estrutural

É um bundle sem rastreabilidade legível. Quando a lógica muda, o auditor precisa voltar ao fonte privado e inferir que o bundle realmente corresponde ao fonte.

### Recomendação

O estado desejável é:

```text
src/**/*.tsx/js
       │
       ├── lint
       ├── typecheck
       ├── unit tests
       ├── build
       ▼
  dist/app.[hash].js
       │
       ▼
    index.html
```

O bundle deve ser produto do build, nunca o artefato manualmente mantido em paralelo.

---

## 4.4 `supabase/fauna-fonte_privado.html`

**Tamanho:** ~343 KB, 5.490 linhas.

Contém a aplicação em JSX dentro de `script type="text/babel"`.

### Problema estrutural central

É essencialmente o repositório de código-fonte, mas está encapsulado em HTML e depende de:

- Babel Standalone via `@7` flutuante;
- React 18.3.1;
- ReactDOM 18.3.1;
- Supabase JS `@2`.

Isso é conveniente para edição manual/experimental, porém ruim para um sistema “LLM-first”, porque a IA precisa compreender que há **dois artefatos de frontend** e que um é fonte e outro é distribuição.

### Recomendação

Substituir o HTML-fonte por arquivos reais, por exemplo:

```text
src/
  App.jsx
  api/
  game/
  auth/
  components/
  features/
  admin/
  legal/
```

E manter `fauna-fonte_privado.html` somente como eventual arquivo de demonstração, ou removê-lo.

---

## 4.5 Componentização atual

A fonte contém dezenas de componentes e funções. Entre os principais domínios foram identificados:

- autenticação e callback;
- `ConsentGate`, `NDAGate` e fluxo legal;
- cartas e modais (`CardFace`, `CardBack`, `NatureCard`, `CardModal`);
- coleção e álbum;
- quiz;
- conquistas;
- check-in/missões;
- mercado;
- trocas;
- família/controle parental;
- conta/configuração;
- ranking/ranqueada;
- notícias;
- personagem/cosméticos/avatar;
- feedback;
- administração/fotos;
- página pública de jogador.

Isso mostra que existe uma boa decomposição **conceitual**, mas ela não está refletida na estrutura de arquivos. A próxima IA deve separar primeiro por domínio, não por “tamanho do arquivo”.

---

# 5. Frontend: problemas críticos de comportamento

## 5.1 `ConsentGate` — FAIL-OPEN

Trecho observado no fonte:

```js
useEffect(()=>{
  db.rpc("app_legal_status_v2")
    .then(({data})=>setStatus(data||{accepted:true}))
    .catch(()=>setStatus({accepted:true}));
},[]);
```

Isto significa que:

```text
RPC funciona → status real é usado.
RPC falha     → aceitação é presumida.
```

Para uma barreira legal, o comportamento correto é o contrário:

```text
RPC funciona → status real.
RPC falha     → estado de erro/bloqueio/retry.
```

### Instrução para a outra IA

Alterar para uma máquina de estados explícita:

```text
loading → accepted
loading → needs_consent
loading → error
```

Nunca converter `error` em `accepted`.

---

## 5.2 `Main` — falha do perfil pode atravessar o NDA

Hoje `loadProfile()` faz a consulta e apenas grava `profile`. O `Main` bloqueia somente se:

```js
if(profile && !profile.nda_accepted_at) {
  return <NDAGate ... />;
}
```

Se a leitura do perfil falhar, `profile` permanece `null`. O teste não distingue:

```text
perfil ainda carregando
```

de

```text
erro ao carregar perfil
```

e pode seguir renderizando a aplicação.

### Correção

Criar `profileState = loading | ready | error`.

Somente `ready` pode avançar para a aplicação.

---

## 5.3 Quiz — erro ao responder vira resposta errada

O método `choose()` faz:

```js
try {
  const { data } = await db.rpc("app_answer_quiz", ...);
  correct = !!data.correct;
} catch(e) {}
setAnswered({correct,...});
```

Portanto, uma falha RPC pode resultar em:

```text
backend caiu → catch → correct=false → UI mostra “errado”
```

Isso é ruim porque transforma uma falha de infraestrutura em estado de jogo.

### Correção

Em erro:

- não marcar `answered`;
- mostrar erro transitório;
- liberar retry;
- não alterar pontuação nem progresso local.

---

## 5.4 Quiz — `finish()` entra em “done” mesmo com erro

A função chama o RPC e, independentemente de sucesso ou falha, executa:

```js
setPhase("done");
onChanged();
loadStatus();
loadKnowledge();
```

Assim a UI pode mostrar fim de quiz mesmo que o servidor não tenha confirmado a finalização.

### Correção

Somente fazer `setPhase("done")` depois de `error == null` e de um retorno válido do banco.

---

# 6. Auditoria do banco e segurança

## 6.1 RLS

As 46 tabelas públicas estão com RLS habilitado. Isso é um ponto forte.

Há, porém, 10 tabelas com RLS ativo e nenhuma policy, o que equivale a “deny by default” para acesso normal:

- `admins`;
- `card_transactions`;
- `conservation_spawn_weights`;
- `daily_checkins`;
- `marketplace_fees`;
- `match_rounds`;
- `matches`;
- `mission_claims`;
- `quiz_answer_options`;
- `ranked_matches`.

Isso é aceitável para tabelas estritamente internas, desde que **todas as funções que precisam delas sejam `SECURITY DEFINER` conscientemente auditadas**.

Não se deve “corrigir” essas tabelas simplesmente adicionando `SELECT` público. O padrão atual parece deliberado em vários casos.

---

## 6.2 Security Advisor — estado atual

O Security Advisor remoto encontrou:

### ERROR

Cinco views `SECURITY DEFINER`:

- `v_education_ranking`;
- `v_market_active`;
- `v_trade_offers_detail`;
- `v_ranked_ranking`;
- `v_ranked_history`.

### WARN

- 74 funções `SECURITY DEFINER` executáveis por `authenticated`.
- proteção contra senhas vazadas desabilitada.
- tabela parental com múltiplas permissive policies no SELECT.

### INFO

10 tabelas com RLS sem policies, listadas acima.

### Interpretação correta

`SECURITY DEFINER` não é uma vulnerabilidade automática. Neste projeto ele é usado para fazer exatamente o trabalho importante de impedir escrita direta em dados internos e concentrar lógica no banco. O problema é **superfície, revisão e princípio do menor privilégio**.

A documentação atual do Supabase recomenda `SECURITY INVOKER` como padrão e, quando `SECURITY DEFINER` é necessário, `search_path = ''` com objetos qualificados pelo schema e execução explicitamente restrita. citeturn136200search0turn136200search8

No projeto auditado, as 94 funções `SECURITY DEFINER` têm `search_path` explicitamente configurado, mas **nenhuma está com `search_path=''`**; todas usam configuração derivada do padrão/pinning para `public`.

Isso não torna o código imediatamente explorável, mas é menos rígido que a recomendação atual.

---

## 6.3 Views

As views:

- `v_education_ranking`;
- `v_market_active`;
- `v_ranked_history`;
- `v_ranked_ranking`;
- `v_trade_offers_detail`

são consumidoras diretas do frontend.

O Postgres cria views, por padrão, avaliadas com as permissões do proprietário. Com `security_invoker=true`, as permissões e RLS do chamador passam a governar o acesso. Essa é precisamente a razão do alerta do Advisor. citeturn136200search4

### Atenção

Não basta executar cegamente:

```sql
ALTER VIEW ... SET (security_invoker = true);
```

Para `v_education_ranking` e `v_ranked_ranking`, por exemplo, a própria finalidade é mostrar um ranking global, enquanto as tabelas-base têm RLS privado. Portanto, mudar a view sem redesenhar a política pode fazer o ranking desaparecer.

### Estratégia recomendada

Separar claramente:

```text
VIEW privada/internal
  → usada por RPCs internas

API RPC pública/controlada
  → devolve apenas campos deliberadamente públicos
```

Para ranking e mercado, uma RPC explícita e auditada pode ser melhor do que uma view privilegiada diretamente exposta.

`v_card_base` é especialmente interessante: ela é usada como view interna por várias RPCs, mas não precisa estar na superfície Data API. Vale avaliar movê-la para um schema privado/internal e deixá-la inacessível diretamente pelo cliente.

---

## 6.4 Grants e superfície da Data API

Apesar do RLS forte, ainda existem grants de tabela no banco. Em especial, `conservation_spawn_weights` aparece com grants de DML para `anon`/`authenticated`, embora sem policy e portanto bloqueada por RLS; isso cria uma defesa em profundidade menos rigorosa do que o necessário.

A recomendação é adotar o modelo:

```text
REVOKE amplo
→ GRANT mínimo explícito
→ RLS
→ policies
→ RPCs para mutações
```

Isso também prepara o projeto para a mudança da Data API em 30 de outubro de 2026: novos objetos no schema público passam a exigir grants explícitos para serem expostos à Data API em projetos existentes. RLS não substitui grants; são camadas diferentes. citeturn136200search3turn136200search12

---

# 7. Auditoria da economia e integridade do jogo

## 7.1 Compra de pacote — BOM

`buy_pack()`:

- verifica existência;
- rejeita pacote gratuito;
- bloqueia saldo de perfil com `FOR UPDATE`;
- verifica saldo;
- debita moeda;
- grava `currency_ledger`;
- cunha cartas;
- grava `pack_openings`.

A transação é um bom padrão.

---

## 7.2 Pacote gratuito — BOM

`open_basic_pack()` usa:

```sql
pg_advisory_xact_lock(hashtextextended('open_basic_pack:'||p_user_id::text, 0));
```

Isso é exatamente o tipo de proteção que deveria ser usado também em outros limites “uma vez por período”.

---

## 7.3 Compra no mercado — BOM

`buy_listing()` faz uma sequência correta de locks:

1. trava anúncio;
2. trava perfis de comprador/vendedor em ordem;
3. verifica saldo;
4. trava carta;
5. verifica proprietário;
6. calcula taxas;
7. move saldo;
8. move propriedade;
9. fecha anúncio;
10. registra transação.

Esse padrão é consideravelmente mais sólido do que a média de implementações geradas por IA.

---

## 7.4 Troca — BOM, com uma ressalva

`respond_trade_offer()`:

- trava a oferta;
- verifica destinatário;
- trava perfis em ordem determinística;
- trava cada carta;
- revalida propriedade;
- bloqueia troca de carta atualmente anunciada;
- faz os movimentos em transação.

Isso é bom.

### Ressalva

`create_trade_offer()` não exige `for_trade=true` nas cartas. Se `for_trade` for apenas um indicador de “disponível para descoberta”, tudo bem. Se o design disser que uma carta precisa estar marcada para troca para poder ser oferecida, o backend precisa validar isso.

---

# 8. Falhas críticas do quiz

Esta é a área prioritária de toda a auditoria.

## 8.1 Limite de perguntas é aplicado apenas no cliente

O frontend chama:

```js
app_start_quiz({p_num_questions:5})
```

Mas o backend `app_start_quiz(p_num_questions)` não impõe que o valor seja 5.

O `start_quiz_session()` usa o valor recebido em `LIMIT p_num_questions`.

A finalização recompensa:

```text
10 moedas por acerto
```

Então o modelo atual permite que um cliente autenticado tente criar uma sessão com mais perguntas do que a interface oferece.

### Correção P0

O servidor deve ser autoridade:

```sql
IF p_num_questions IS DISTINCT FROM 5 THEN
    RAISE EXCEPTION 'Quantidade de perguntas invalida';
END IF;
```

Ou, se houver intenção de aceitar 1–5 no futuro, impor explicitamente `1 <= p_num_questions <= 5` e definir uma política de recompensa coerente.

---

## 8.2 Resposta correta + reenvio da mesma pergunta

`app_answer_quiz()` retorna:

```json
{
  "correct": true/false,
  "correct_option_id": "..."
}
```

`answer_quiz_question()` permite que a mesma linha seja atualizada novamente.

O controle `v_prev` impede apenas novo ajuste do `knowledge_rank`, mas não impede que:

```text
resposta A
↓
estado salvo
↓
servidor revela B como correta
↓
mesma pergunta é enviada novamente
↓
estado final passa a “correto”
↓
finish_quiz_session calcula pela versão final
```

Isso é uma falha real de integridade, não apenas um detalhe de UX.

### Correção P0

Adicionar uma coluna, por exemplo:

```sql
answered_at timestamptz
```

E tornar a resposta **imutável**:

```sql
SELECT ...
FROM quiz_session_answers
WHERE session_id = p_session_id
  AND question_id = p_question_id
FOR UPDATE;

IF selected_option_id IS NOT NULL THEN
    RAISE EXCEPTION 'Pergunta ja respondida';
END IF;
```

A primeira resposta válida é a única que conta.

Depois disso, o sistema pode revelar a opção correta ao jogador, porque ela não poderá mais ser usada para reescrever o resultado.

---

## 8.3 Validação do tempo

`p_time_taken` é controlado principalmente pela interface. O backend usa o valor para decidir se a resposta está dentro do limite.

Deve existir pelo menos:

```sql
IF p_time_taken IS NOT NULL AND p_time_taken < 0 THEN
    RAISE EXCEPTION 'Tempo invalido';
END IF;
```

Melhor ainda: registrar timestamps do servidor e usar o intervalo entre eventos server-side quando o modelo do jogo permitir.

---

## 8.4 Limite diário do quiz também precisa de lock

O wrapper conta as sessões do dia antes de criar uma nova. Duas chamadas simultâneas podem ler o mesmo contador antes que qualquer uma veja a outra.

Recomenda-se reutilizar o padrão de advisory lock:

```sql
pg_advisory_xact_lock(
  hashtextextended('quiz_daily:'||auth.uid()::text,0)
);
```

Só depois disso contar e criar a sessão.

---

# 9. Ranqueada

## 9.1 O snapshot parece deliberado

`app_set_ranked_team()` grava uma cópia JSON das cartas e atributos.

A própria UI fala em “snapshot” do time.

Isso é uma escolha de design válida para permitir que um adversário jogue contra a configuração salva de outro jogador.

### Mas a decisão precisa ser formalizada

Hoje nada força que `card_id` do snapshot continue pertencendo ao jogador depois de troca/queima.

Há dois modelos possíveis:

### Modelo A — snapshot histórico

A ranqueada congela o time. Trocar/queimar depois não altera o time já salvo.

Nesse caso, documentar isso e tratar o snapshot como entidade competitiva independente.

### Modelo B — time vinculado à coleção atual

A qualquer tentativa de jogar, o sistema valida os cinco IDs e propriedade atual. Se algum não existir mais, o time é invalidado.

Não misturar os dois modelos.

---

## 9.2 Concurrency da ranqueada

`app_ranked_play()` lê ratings e atualiza ratings, mas não trava os dois `ranked_teams` antes da resolução.

Duas partidas simultâneas envolvendo o mesmo jogador podem:

- ler o mesmo rating inicial;
- calcular deltas a partir do mesmo estado;
- sobrescrever uma atualização com outra.

### Correção P1

Depois de localizar os dois players:

```sql
SELECT player_id, rating, team
FROM ranked_teams
WHERE player_id IN (v_me, v_op)
ORDER BY player_id
FOR UPDATE;
```

E só então calcular/atualizar.

A ordem determinística reduz risco de deadlock.

---

# 10. Check-in e limites concorrentes

## 10.1 `app_checkin()` tem corrida real

A função lê `daily_checkins` sem `FOR UPDATE`.

Duas requisições simultâneas podem fazer:

```text
ambas leem last_date antigo
↓
ambas calculam reward
↓
ambas atualizam perfil
↓
ambas recebem moeda
```

A existência da chave única ajuda a impedir duplicação física da linha, mas não impede duas recompensas antes da resolução concorrente.

### Correção P1

Adicionar advisory lock por usuário antes do cálculo, ou inicializar a linha e então usar `SELECT ... FOR UPDATE`.

---

## 10.2 `app_set_showcase()`

A função conta quantas cartas em destaque existem e aceita o novo estado.

Duas chamadas concorrentes podem ver, por exemplo, 7 cartas e ambas adicionar uma oitava/nona.

### Correção

Usar lock por usuário antes de contar e atualizar.

---

## 10.3 `app_request_data_action()`

O limite de 5 pedidos/24h também é contado antes da inserção sem lock. É uma questão menor, mas o padrão deve ser o mesmo para qualquer rate-limit baseado em contagem.

---

# 11. Username

`app_set_username()` faz:

```sql
where lower(username) = lower(v_clean)
```

mas a constraint do banco é `UNIQUE(username)`, case-sensitive.

Isso deixa uma diferença entre:

```text
Alice
alice
```

### Problema de concorrência

Duas transações podem passar na verificação manual simultaneamente.

### Correção P1

Criar garantia no banco:

```sql
CREATE UNIQUE INDEX profiles_username_lower_key
ON public.profiles (lower(username));
```

Depois tratar `unique_violation` para retornar erro amigável.

A IA não deve depender apenas do `SELECT EXISTS` antes de `UPDATE`.

---

# 12. Auditoria / trilha de cartas

`app_burn_card()` registra `burn` em `card_transactions` antes de apagar a carta. Bom.

`buy_listing()` registra venda. Bom.

`generate_card()` registra `mint`. Bom.

Mas `app_paste_card()` consome a carta ao preencher o álbum sem inserir um evento equivalente explícito de transação antes do `DELETE`.

### Recomendação

Adicionar algo como:

```text
album_paste
```

ou

```text
consume_album
```

na trilha de transações.

Isso é importante porque o jogo possui economia e ativos colecionáveis. Toda destruição/consumo de uma carta deveria responder claramente à pergunta:

> “Por qual motivo esta carta deixou de existir?”

---

# 13. `generate_card()`

É uma das partes tecnicamente melhores do backend.

## Fluxo

1. escolhe espécie;
2. usa peso de conservação quando aplicável;
3. escolhe bioma;
4. escolhe foto;
5. sorteia estilo de arte;
6. trava `card_supply`;
7. controla `max_supply`;
8. sorteia atributos;
9. calcula float;
10. deriva raridade;
11. insere carta;
12. insere atributos;
13. registra mint.

### Pontos positivos

- lock de supply;
- fallback para arte comum;
- proteção contra estilo especial sem supply configurado;
- precisão numérica preservada;
- transação centralizada.

### Melhoria importante

Vários números de balanceamento estão hardcoded no código SQL:

- probabilidades de arte;
- 6% de arte alternativa;
- 15% de bônus de bioma;
- valores de scrap;
- preço fixo do pacote;
- recompensas de quiz/check-in/missões;
- constantes de Elo.

Para um jogo que será balanceado por IA ao longo do tempo, é melhor separar:

```text
regra estrutural
≠
parâmetro de balanceamento
```

Um catálogo versionado de configuração pode conter esses parâmetros e permitir que a IA altere números sem reescrever toda a função.

---

# 14. Família, consentimento e permissões

## O que está bom

`app_my_access()` tem comportamento fail-closed para menores sem controle parental:

- compras desabilitadas;
- ranqueada desabilitada.

Os RPCs de compra e ranqueada também revalidam esse controle no banco.

Isso é bom porque a UI não é a autoridade.

## O que precisa melhorar

O sistema aceita no `app_accept_terms_v2()` uma declaração de consentimento parental. A confirmação de identidade/autoridade do responsável é uma questão de produto/processo jurídico, não apenas de SQL.

Portanto, o relatório não certifica conformidade legal. A camada de software deve apenas garantir que as declarações e permissões necessárias sejam obrigatoriamente respeitadas no fluxo.

---

# 15. Segurança de autenticação

A aplicação é um SPA client-only e usa:

```js
flowType: "implicit"
persistSession: true
autoRefreshToken: true
detectSessionInUrl: true
```

O implicit flow é suportado para aplicações puramente client-side; tokens aparecem no fragmento da URL e a biblioteca os persiste localmente. PKCE é a opção recomendada quando há backend/SSR e é a direção recomendada para OAuth moderno. citeturn136200search2turn136200search1turn136200search10

Portanto:

- **não classificar implicit flow como vulnerabilidade crítica neste SPA específico**;
- mas, se a arquitetura evoluir para SSR/rotas protegidas servidor-side, migrar para PKCE.

### Local storage

A aplicação usa `localStorage` explicitamente para apenas duas coisas relacionadas ao jogo, incluindo o último time. O próprio Supabase pode manter sessão no armazenamento local quando não há SSR.

A recomendação arquitetural é reduzir a quantidade de estado sensível persistido diretamente pela aplicação e usar o mecanismo oficial do cliente, evitando armazenar dados de autorização próprios.

---

# 16. Configuração de autenticação

`config.toml` tem:

- signup habilitado;
- anonymous sign-in desabilitado;
- refresh-token rotation habilitada;
- senha mínima 6;
- requisitos de composição vazios;
- confirmações de email desabilitadas;
- secure password change desabilitado.

Como arquivo local/dev, parte disso pode ser deliberado. Porém, para produção, a configuração precisa ser comparada explicitamente com o Auth remoto.

A documentação atual do Supabase recomenda pelo menos 8 caracteres e recomenda proteção contra senhas vazadas; o projeto remoto foi sinalizado com leaked-password protection desabilitada. citeturn136200search5

### Correção recomendada

Para produção:

```text
minimum_password_length >= 8
leaked password protection = enabled
secure password change = enabled
email confirmation = decisão explícita de produto
```

A política não deve ficar duplicada em vários componentes do frontend. O texto de `savePassword` hoje usa mínimo 6 no cliente. A validação real deve ser a do servidor; o cliente apenas pode antecipar o feedback.

---

# 17. Storage

Há um único bucket:

```text
fotos
```

Ele está configurado como **público**, sem limite de MIME ou tamanho reportado no bucket remoto.

### Interpretação

Isso é compatível com o caso de uso de fotografias públicas de cartas. Não é necessário tornar as fotos privadas só porque o restante do banco é privado.

### Melhorias

- definir `allowed_mime_types` se o fluxo permitir;
- definir limite de tamanho no bucket;
- validar extensão/MIME também no processo de upload;
- impedir que caminho de arquivo seja interpretado como autorização;
- manter metadados do fotógrafo em tabela separada e expor apenas os campos necessários.

A migration final sobre `photographers` demonstra que a preocupação com PII já foi percebida e corrigida parcialmente. **Não desfazer essa proteção** concedendo `SELECT *` indiscriminado.

---

# 18. Performance

O Performance Advisor reportou:

- 44 índices atualmente considerados não utilizados;
- 1 warning de múltiplas permissive policies em `parental_controls`.

### Sobre os 44 índices

Isso não significa automaticamente que 44 índices devem ser apagados. Em alpha, vários podem ter sido criados preventivamente ou ainda não ter dados suficientes para mostrar uso.

Antes de remover:

1. verificar frequência real das queries;
2. revisar FKs e joins críticos;
3. comparar planos de `EXPLAIN ANALYZE`;
4. remover apenas após observar carga representativa.

### `parental_controls`

Há duas policies permissivas de SELECT, uma para a criança e outra para o guardião. Elas são semanticamente diferentes, portanto a correção não deve ser “apagar uma policy” sem revisar o predicado.

A melhoria é documentar por que as duas existem ou consolidá-las em uma expressão única, se isso mantiver a semântica.

---

# 19. Reprodutibilidade — maior problema arquitetural depois do quiz

## 19.1 `config.toml` aponta para projeto diferente

O arquivo contém:

```toml
project_id = "wlwreturn-backup"
```

enquanto o projeto remoto auditado é `wlwreturn`.

O `.temp/project-ref` aponta para o projeto remoto correto.

Isso é drift de configuração e precisa ser resolvido.

---

## 19.2 `seed.sql` não está no ZIP

O `config.toml` declara:

```toml
[db.seed]
enabled = true
sql_paths = ["./seed.sql"]
```

Mas não há `supabase/seed.sql` no arquivo recebido.

Portanto, um reset local completo não reproduz o conteúdo atual do projeto.

---

## 19.3 Não existe baseline do schema

As 69 migrations são incrementais. A primeira já altera funções/tabelas que existiam antes dela. Não há migration inicial contendo `CREATE TABLE` para construir as entidades-base.

Isso significa:

```text
ZIP atual
+ banco vazio
= NÃO reproduz o jogo.
```

Para um sistema “LLM-first” isso é especialmente perigoso. A outra IA pode gerar uma nova migration perfeita e ainda assim não conseguir validar a instalação em um ambiente vazio.

### Solução definitiva

Criar um estado canônico reproduzível:

```text
supabase/
  migrations/
    00000000000000_baseline.sql
    ...
  seed.sql
  config.toml
```

ou, melhor ainda, manter migrations históricas completas desde o início, com schema declarado e seed versionado.

---

# 20. GitHub / controle de versão

O ZIP não contém `.git` nem `.github`. A busca no GitHub conectado não permitiu identificar com segurança um repositório correspondente ao projeto apenas por nomes semelhantes. Portanto, **não foi feita uma auditoria da história real de commits, branches, PRs e CI do repositório de produção**.

Isso deve ser tratado como uma limitação de escopo, não como uma conclusão de que o GitHub não existe.

### Para a outra IA

Não presumir que:

```text
ZIP = branch atual
```

É preciso estabelecer uma regra formal:

```text
GitHub main
    ↓
Supabase migrations
    ↓
Deploy
    ↓
versão da aplicação
```

Cada deploy deve permitir responder:

> qual commit de código está no ar e qual versão de migration está aplicada no banco?

---

# 21. Migrations — inventário completo e interpretação

As 69 migrations do pacote, em ordem, são as seguintes.

| # | Migration | Papel principal |
|---:|---|---|
| 01 | `20260617160654_quiz_least_recently_seen_selection.sql` | Altera `start_quiz_session()` para escolher perguntas menos vistas/mais antigas. Boa estratégia de variedade educacional. |
| 02 | `20260617162101_tighten_match_rewards.sql` | Reescreve `app_match_play()` para endurecer recompensa de partidas e regras de resolução. |
| 03 | `20260617202123_perfect_quiz_pack_once_per_day.sql` | Reescreve `finish_quiz_session()` para permitir pacote de quiz perfeito uma vez/dia. |
| 04 | `20260617202143_escalating_extra_pack_price.sql` | Primeira implementação de preço crescente para pacote extra. |
| 05 | `20260617202156_app_extra_pack_price.sql` | Cria a função pública `app_extra_pack_price()`. |
| 06 | `20260617204325_fixed_extra_pack_price_150.sql` | Substitui o preço escalonado por preço fixo de 150 e sincroniza RPC. Indica iteração de balanceamento muito rápida. |
| 07 | `20260618001422_account_level_and_avatars.sql` | Adiciona níveis, avatars e tabelas `avatars`/`player_avatars`, XP e RPCs de conta. |
| 08 | `20260618020031_quiz_flat_reward_per_correct.sql` | Simplifica recompensa do quiz para valor fixo por acerto. |
| 09 | `20260618095137_quiz_extremo_and_answer_reveals_correct.sql` | Adiciona dificuldade extrema e mecanismo de revelação de resposta correta. Hoje participa do problema de anti-cheat quando combinado com reenvio. |
| 10 | `20260618095214_match_play_returns_correct_option.sql` | Faz `app_match_play()` retornar a opção correta após resolução da rodada. É aceitável porque a jogada é encerrada na mesma transação. |
| 11 | `20260618101324_knowledge_rank_schema_and_helpers.sql` | Cria rank de conhecimento e helpers de dificuldade. |
| 12 | `20260618145631_answer_quiz_updates_knowledge_rank.sql` | Liga respostas ao `knowledge_rank`. |
| 13 | `20260618145645_start_quiz_adaptive_by_rank.sql` | Faz seleção de perguntas adaptada ao rank. |
| 14 | `20260618145717_achievements_knowledge_rank.sql` | Estende `evaluate_achievements()` para rank de conhecimento. |
| 15 | `20260618145811_seed_knowledge_achievements.sql` | Dados iniciais de conquistas de conhecimento. |
| 16 | `20260618183010_achievements_insignia_columns.sql` | Adiciona colunas de insígnias às conquistas. |
| 17 | `20260618183021_seed_insignia_avatars.sql` | Dados de avatars/insígnias. |
| 18 | `20260618183050_evaluate_achievements_insignia_types.sql` | Amplia `evaluate_achievements()` para tipos de insígnia. |
| 19 | `20260618183111_seed_insignias.sql` | Seed adicional de insígnias. |
| 20 | `20260618183206_ranked_play_evaluates_achievements.sql` | Integra ranqueada com avaliação de conquistas. |
| 21 | `20260618195221_evaluate_achievements_biome_distinct_species.sql` | Conquistas por bioma e espécies distintas. |
| 22 | `20260618195239_tiered_biome_insignias.sql` | Tiers das insígnias por bioma. |
| 23 | `20260618201106_tier_quiz_rank_insignias.sql` | Tiers de insígnia ligados ao quiz/rank. |
| 24 | `20260618201116_tier_arena_insignias.sql` | Tiers de arena. |
| 25 | `20260618201125_tier_collection_insignias.sql` | Tiers de coleção. |
| 26 | `20260618201137_tier_species_mastery_insignias.sql` | Tiers de domínio de espécies. |
| 27 | `20260618210852_character_cosmetics_schema.sql` | Estrutura de cosméticos e `player_cosmetics`. |
| 28 | `20260618210927_character_cosmetics_rpcs.sql` | RPCs para personagem, avatar e compra de cosméticos. |
| 29 | `20260619220101_harden_security_revoke_internal_execute_and_write_grants.sql` | Primeira grande fase de endurecimento: revoga execução/escrita de funções internas. Bom sinal arquitetural. |
| 30 | `20260620000341_pin_search_path_remaining_functions.sql` | Pina search path de funções restantes. Útil, mas ainda não está no padrão mais rígido `search_path=''`. |
| 31 | `20260620005211_profile_showcase_visibility_and_public_profile.sql` | Visibilidade de cartas, showcase e perfil público. |
| 32 | `20260620010945_fix_public_profile_only_unlocked_insignias.sql` | Corrige perfil público para exibir apenas insígnias desbloqueadas. |
| 33 | `20260620103807_showcase_limit_message_destaque.sql` | Refina limite de 8 cartas em destaque. |
| 34 | `20260620112732_generate_card_preserve_small_value_precision.sql` | Preserva precisão pequena no `generate_card()`. |
| 35 | `20260620160513_v_card_base_derive_photo_and_photographer.sql` | Cria `v_card_base` derivando foto/fotógrafo. É uma view interna central. |
| 36 | `20260620163337_public_profile_add_rank_positions_and_seals_slot.sql` | Adiciona posições de ranking/slot de seals ao perfil público. |
| 37 | `20260621051731_quiz_add_questions_for_new_species_batch1.sql` | Grande seed de perguntas do quiz para novas espécies. |
| 38 | `20260621052718_quiz_add_behavior_ecology_and_extremas_batch2.sql` | Seed de perguntas de comportamento/ecologia/extremas. |
| 39 | `20260621052814_quiz_cover_remaining_two_marrecas_batch3.sql` | Completa cobertura de duas espécies restantes. |
| 40 | `20260621055911_nda_acceptance_column_and_rpc.sql` | Adiciona NDA ao perfil e cria `app_accept_nda()`. |
| 41 | `20260621124617_harden_anon_execute_and_view_exposure.sql` | Endurece exposição de views e execução anônima. |
| 42 | `20260621173823_restrict_private_select_policies_to_authenticated.sql` | Restringe leitura privada ao papel `authenticated`. |
| 43 | `20260621173853_restrict_legal_acceptance_select_to_authenticated.sql` | Ajusta privacidade de dados legais. |
| 44 | `20260621174135_optimize_rls_auth_uid_initplan.sql` | Otimiza policies/RLS para evitar reavaliação desnecessária de `auth.uid()`. |
| 45 | `20260621174149_add_covering_indexes_for_foreign_keys.sql` | Índices de suporte às FKs. Parte da base de performance. |
| 46 | `20260621180559_conservation_spawn_weights_table.sql` | Cria pesos de spawn por status de conservação. |
| 47 | `20260621180626_generate_card_weighted_by_conservation.sql` | Faz `generate_card()` usar pesos de conservação. |
| 48 | `20260621230440_photos_add_focal_point.sql` | Adiciona ponto focal de fotografia. |
| 49 | `20260621230456_card_views_expose_focal_point.sql` | Expõe focal point em views de cartas. |
| 50 | `20260621230515_admin_photo_management_rpcs.sql` | RPCs de administração de fotos: listagem, status e foco. |
| 51 | `20260622110123_card_views_expose_max_supply.sql` | Expõe `max_supply` nas views de cartas. |
| 52 | `20260623074936_match_question_aleatoria.sql` | Faz pergunta da partida ser aleatória entre perguntas ativas. |
| 53 | `20260623113436_family_accounts_foundation.sql` | Estrutura inicial de família/controle parental. |
| 54 | `20260623122544_consent_age_flow_v2.sql` | Cria fluxo jurídico v2 baseado em data de nascimento/consentimento. |
| 55 | `20260623132504_family_linking_backend.sql` | Backend para convite, vínculo, controles e unlink de família. |
| 56 | `20260623133130_permission_gates_purchases_ranked.sql` | Introduz `app_child_allowed()` e gates de compra/ranqueada. |
| 57 | `20260623134357_app_my_access.sql` | Expõe ao cliente a matriz de acesso calculada no servidor. |
| 58 | `20260623173105_parental_visibility_flags.sql` | Expande flags de visibilidade/permissão parental. |
| 59 | `20260623175212_quiz_daily_reset_midnight.sql` | Define limite diário do quiz com virada em horário de Brasília. |
| 60 | `20260623222612_profile_country_field.sql` | Adiciona país ao perfil e sincroniza consentimento v2. |
| 61 | `20260624160141_achievements_claim_model.sql` | Muda conquistas para modelo explícito de “desbloqueada vs resgatada”. Boa decisão econômica. |
| 62 | `20260625095710_cosmetics_catalog_expansion_olhos_slot_v2.sql` | Expande catálogo de cosméticos para slot de olhos. |
| 63 | `20260706215042_rls_performance_initplan_optimization.sql` | Segunda rodada de otimização de policies/RLS. |
| 64 | `20260707183228_create_app_match_status.sql` | Cria RPC de status de partida. |
| 65 | `20260709012754_lock_down_photographers_pii.sql` | Restringe PII de fotógrafos. Excelente direção. |
| 66 | `20260709012810_burn_card_surface_supply_inconsistency.sql` | Corrige consistência do `card_supply` ao queimar cartas. |
| 67 | `20260709095730_open_basic_pack_concurrency_lock.sql` | Adiciona advisory lock ao pacote gratuito. Excelente correção concorrente. |
| 68 | `20260709095837_generate_card_guard_uncapped_special_styles.sql` | Impede cunhagem de estilos especiais sem oferta configurada. Boa proteção de supply. |
| 69 | `20260724020109_fix_photographers_access_broke_card_view.sql` | Recupera acesso mínimo de fotógrafos após hardening. É importante manter apenas os campos públicos necessários. |

### Padrão observado no histórico

O histórico mostra uma evolução típica de projeto gerado/ajustado por IA: muitas migrations pequenas, correções rápidas e regras de balanceamento alteradas sequencialmente. Isso não é ruim por si só, mas aumenta a importância de:

- testes de regressão;
- baseline reproduzível;
- convenção de nomes;
- revisão de invariantes;
- remoção de funções obsoletas;
- testes de concorrência.

---

# 22. Funções e superfície da API

O frontend chama 71 funções `app_*`. Todas existem no banco com assinaturas esperadas.

Além delas, o schema público ainda contém funções legadas ou internas como:

- `app_accept_terms`;
- `app_legal_status`;
- `app_create_trade`;
- `answer_quiz_question`;
- `buy_pack`;
- `burn_card`;
- `generate_card`;
- `start_quiz_session`;
- várias funções auxiliares de conquistas, XP e trades.

Isso é normal internamente, mas a arquitetura ideal é separar:

```text
public/api
  RPCs estritamente destinadas ao cliente

private/internal
  helpers e funções nunca chamadas diretamente pelo browser
```

A outra IA deve evitar continuar criando toda função nova no `public` apenas porque é conveniente para a API.

---

# 23. Admin

Os RPCs administrativos fazem verificação explícita:

```sql
if not exists (
  select 1 from admins where user_id = auth.uid()
) then
  raise exception 'Acesso restrito';
end if;
```

Isso é correto.

### Melhorias

- centralizar `is_admin()` para evitar repetição;
- manter todos os endpoints admin separados da API de jogador;
- registrar eventos administrativos sensíveis em log de auditoria;
- exigir motivo em operações de concessão de moeda, já parcialmente suportado em `app_admin_grant_coins`;
- considerar reautenticação para ações administrativas mais destrutivas.

---

# 24. Dead code / manutenção

Foi identificado pelo menos um componente antigo, `PerfilTab`, que existe no fonte mas não participa do roteamento principal atual.

Também existem múltiplos padrões como:

```js
catch(e){}
```

em várias áreas.

### Regra para a próxima IA

Não apagar automaticamente tudo que parece não utilizado. Fazer:

```text
1. mapear referências
2. confirmar que não existe rota/dependência indireta
3. marcar como deprecated
4. remover em migration/commit separado
```

No frontend, erros nunca devem ser silenciosamente descartados em operações que alteram estado.

---

# 25. Testes — estado atual

## O que foi possível testar estático

- sintaxe JS do bundle: **OK**;
- chamadas RPC do frontend vs funções remotas: **OK, 71/71 presentes**;
- busca de padrões perigosos (`eval`, `new Function`, `innerHTML`, etc.): **sem ocorrência relevante no fonte**;
- estrutura de migrations: **69 arquivos presentes e aplicados remotamente**;
- RLS e grants: auditados diretamente no banco;
- Security Advisor e Performance Advisor: consultados remotamente.

## O que NÃO foi comprovado

Não foi possível concluir uma suíte de E2E autenticada real em navegador neste ambiente. O smoke test de navegador não completou por dependências/CDN/rede do ambiente de execução.

Portanto, esta auditoria **não deve ser descrita como “100% testada”**. Ela é uma auditoria estática + inspeção estrutural + inspeção viva do Supabase, não um certificado de execução perfeita.

---

# 26. Matriz de testes obrigatória para a próxima IA

## 26.1 Testes de segurança por papel

Para cada RPC mutável:

| Cenário | Deve funcionar? |
|---|---|
| sem sessão | Não |
| usuário autenticado agindo sobre seus próprios dados | Sim, quando previsto |
| usuário A agindo sobre dados de B | Não |
| child sem autorização | Não |
| guardian com autorização | Sim, quando previsto |
| admin | Sim, somente endpoints admin |
| usuário comum chamando endpoint admin | Não |

---

## 26.2 Testes de economia

Após cada operação:

```text
saldo_final = saldo_inicial + soma(currency_ledger)
```

Sempre que aplicável.

Também validar:

```text
cada card_instance tem no máximo um owner
cada anúncio ativo referencia uma carta existente e pertencente ao seller
cada carta queimada deixa de existir e possui evento de burn
cada carta negociada possui evento de trade
cada carta vendida possui evento de sale
cada carta gerada possui evento de mint
```

---

## 26.3 Testes de concorrência

Disparar duas chamadas simultâneas para:

- `app_open_pack`;
- `app_checkin`;
- `app_claim_mission`;
- `app_claim_alpha_welcome`;
- `app_claim_achievement`;
- `app_set_showcase`;
- `app_request_data_action`;
- `app_start_quiz`;
- `app_ranked_play`;
- `app_buy_listing`;
- `app_respond_trade`.

O resultado deve ser **uma única mutação lógica**, mesmo que existam duas requisições.

---

## 26.4 Testes anti-cheat do quiz

### Teste A — quantidade

```text
app_start_quiz(5) → OK
app_start_quiz(6) → ERRO
app_start_quiz(100) → ERRO
app_start_quiz(-1) → ERRO
```

### Teste B — reenvio

```text
responde questão uma vez → OK
responde mesma questão segunda vez → ERRO
```

### Teste C — revelação

```text
responde errado
recebe correct_option_id
não consegue regravar a resposta
```

### Teste D — pontuação

A recompensa final deve refletir somente as primeiras respostas efetivamente registradas.

### Teste E — concorrência

Duas submissões simultâneas da mesma questão devem produzir apenas um resultado válido.

---

# 27. Plano de correção recomendado

## P0 — antes de qualquer ampliação de usuários

### P0.1 — corrigir integridade do quiz

Criar migration nova, por exemplo:

```text
20261006120000_harden_quiz_integrity.sql
```

Ela deve:

- impor limite de perguntas no RPC de entrada;
- impedir resposta duplicada;
- validar tempo não negativo;
- proteger limite diário com lock;
- garantir que a recompensa dependa da primeira resposta;
- impedir finalização duplicada;
- adicionar índices necessários para `session_id/question_id` se não existirem.

### P0.2 — corrigir gates fail-open

Frontend:

- `ConsentGate`: erro não pode significar aceito;
- `Main`: perfil não carregado não pode significar NDA aceito;
- `QuizTab`: erro RPC não pode significar resposta errada/fim do jogo.

### P0.3 — views privilegiadas

Fazer revisão das cinco views sinalizadas:

```text
v_education_ranking
v_market_active
v_trade_offers_detail
v_ranked_ranking
v_ranked_history
```

Escolher, para cada uma:

```text
A) security_invoker + RLS/policy apropriada
ou
B) remover exposição direta e substituir por RPC controlada
```

Não executar mudança em massa sem testar o efeito no frontend.

---

# 28. P1 — integridade de produção

1. Lock concorrente no `app_checkin()`.
2. Lock concorrente no showcase.
3. Lock na ranqueada.
4. Unique index case-insensitive para username.
5. Auditoria de `card_transactions` no consumo para álbum.
6. Definição formal do modelo de snapshot de ranked team.
7. Separação de funções `api` e `internal`.
8. Redução de `SECURITY DEFINER` desnecessário.
9. Migrar functions para `search_path=''` + schema qualification quando possível.
10. Grants explícitos e default privileges restritos.
11. Revisar permissões do bucket `fotos`.
12. Habilitar proteção contra senhas vazadas no ambiente de produção.

---

# 29. P1 — reprodutibilidade

Criar:

```text
baseline / schema inicial
seed.sql
package.json
lockfile
build script
lint script
test script
CI workflow
```

E remover o drift:

```text
config.toml project_id
vs
.temp project ref
```

A configuração deve ter uma única fonte de verdade.

---

# 30. P2 — refatoração

Migrar o monólito para módulos por domínio:

```text
src/
  app/
  auth/
  api/
  cards/
  collection/
  quiz/
  matches/
  ranked/
  market/
  trades/
  achievements/
  family/
  cosmetics/
  profile/
  admin/
  legal/
  shared/
```

O ponto não é adotar uma arquitetura sofisticada. É garantir que uma IA consiga alterar um domínio sem tocar inadvertidamente em nove outros.

---

# 31. Padrão de desenvolvimento “LLM-first” recomendado

A frase operacional para a outra IA deve ser:

> **Nunca confie na UI para garantir regra de jogo. Nunca trate o cliente como autoridade. Toda mutação econômica deve ser autorizada e validada no PostgreSQL. Toda regra de limite deve ser resistente a concorrência. Todo erro de backend deve preservar o estado anterior. Toda mudança deve ser reproduzível por migration e testável em banco vazio.**

## Ordem obrigatória para qualquer alteração futura

```text
1. definir invariantes
2. alterar schema/migration
3. alterar RPC server-side
4. adicionar teste SQL/RPC
5. alterar frontend
6. adicionar teste de erro/concurrency
7. build
8. smoke test
9. comparar migrations aplicadas
10. somente então publicar
```

### Exemplo de invariante

Em vez de pedir:

> “Melhore o quiz.”

a IA deve receber:

```text
INVARIANTE QUIZ-01
Uma questão de uma sessão pode receber no máximo uma resposta efetiva.

INVARIANTE QUIZ-02
Quantidade máxima de perguntas por sessão = 5.

INVARIANTE QUIZ-03
A recompensa é derivada somente das respostas efetivamente gravadas.

INVARIANTE QUIZ-04
Falha de RPC não altera estado de jogo no cliente.

INVARIANTE QUIZ-05
Duas requisições simultâneas não podem criar mais de uma recompensa lógica para a mesma operação.
```

Isso é muito mais fácil de validar automaticamente.

---

# 32. Modelo de definição de “pronto”

O projeto só deve receber o status **PRODUCTION READY** quando todos os itens abaixo forem verdadeiros:

```text
[ ] quiz não pode ser farmado por parâmetro adulterado
[ ] quiz não aceita segunda resposta
[ ] limites diários são atômicos
[ ] consentimento é fail-closed
[ ] NDA é fail-closed
[ ] views Security Advisor revisadas
[ ] funções SECURITY DEFINER justificadas
[ ] grants explícitos
[ ] username é unique case-insensitive
[ ] check-in concorrente é seguro
[ ] showcase concorrente é seguro
[ ] ranked concurrency é segura
[ ] ledger cobre todas as mutações econômicas relevantes
[ ] schema pode ser reconstruído do zero
[ ] seed existe e é reproduzível
[ ] build é determinístico
[ ] frontend fonte e bundle são gerados no mesmo pipeline
[ ] CI testa migrations
[ ] CI testa RPCs
[ ] CI testa invariantes econômicas
[ ] E2E testa autenticação e fluxos principais
[ ] observabilidade de erros existe
[ ] secrets/config são separados do source
```

---

# 33. Checklist operacional para a próxima IA

## Banco

```text
[ ] Ler migrations antes de escrever novas migrations.
[ ] Nunca editar migration já aplicada.
[ ] Toda mudança nova em migration nova.
[ ] Toda função de mutação deve validar auth.uid().
[ ] Preferir SECURITY INVOKER.
[ ] Se SECURITY DEFINER: justificar, limitar execute, fixar search_path de forma segura.
[ ] Toda operação com moeda deve ter ledger correspondente.
[ ] Toda operação de ativo deve ter lock apropriado.
[ ] Todo limite temporal/constrangimento deve ser concorrente-safe.
```

## Frontend

```text
[ ] Nunca usar catch vazio em mutação.
[ ] Nunca interpretar erro como sucesso.
[ ] Nunca deixar loading e error no mesmo estado null.
[ ] Nenhuma regra importante deve existir só no JSX.
[ ] Fonte deve ser modular.
[ ] Bundle deve ser gerado automaticamente.
```

## Dados

```text
[ ] Não expor PII só porque existe uma tabela.
[ ] Não transformar tabelas internas em públicas apenas para facilitar uma view.
[ ] Preferir RPCs para agregações públicas deliberadas.
```

---

# 34. Conclusão final

O projeto **não é um código “ruim” que precisa ser refeito**. Pelo contrário: há várias decisões tecnicamente boas, especialmente a centralização de mutações no PostgreSQL, o uso de RLS, o lock do pacote gratuito, a proteção do mercado e das trocas, a separação de dados privados e públicos e as migrations específicas de hardening.

O problema é que o projeto chegou a um ponto em que **a lógica funciona melhor do que a engenharia de controle ao redor dela**.

A aplicação consegue jogar, mas ainda não possui as garantias que tornam uma aplicação de jogo econômica realmente confiável contra cliente hostil, falhas transitórias, chamadas simultâneas e reconstrução do ambiente.

A prioridade absoluta deve ser:

```text
QUIZ INTEGRITY
      ↓
FAIL-CLOSED LEGAL/ACCESS
      ↓
VIEWS / DEFINER / GRANTS
      ↓
CONCURRENCY
      ↓
REPRODUCIBILITY
      ↓
TESTS + CI
      ↓
REFACTORING
```

Em outras palavras: **não é necessário jogar fora o núcleo do WildLens**. É necessário transformar o que já funciona em um sistema com invariantes verificáveis e autoridade única no backend.

---

# 35. Referências técnicas externas

- Supabase — Database Functions / `SECURITY INVOKER` vs `SECURITY DEFINER`: https://supabase.com/docs/guides/database/functions
- Supabase — Views / `security_invoker`: https://supabase.com/docs/guides/database/views
- Supabase — Password security: https://supabase.com/docs/guides/auth/password-security
- Supabase — Password-based Auth: https://supabase.com/docs/guides/auth/passwords
- Supabase — PKCE flow: https://supabase.com/docs/guides/auth/sessions/pkce-flow
- Supabase — Implicit flow: https://supabase.com/docs/guides/auth/sessions/implicit-flow
- Supabase — Changelog: Data API explicit grants para novas tabelas: https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically

---

# APÊNDICE A — inventário de arquivos não-migration

| Arquivo | Função | Avaliação |
|---|---|---|
| `supabase/.temp/cli-latest` | versão da CLI local vinculada | útil para diagnóstico; não é fonte de configuração de produção |
| `supabase/.temp/gotrue-version` | versão do serviço Auth local | metadata |
| `supabase/.temp/linked-project.json` | metadata do projeto vinculado | útil, mas pode divergir de `config.toml` |
| `supabase/.temp/pooler-url` | URL de conexão do pooler | **sensível; não deve circular** |
| `supabase/.temp/postgres-version` | versão do Postgres remoto/local | metadata; coerente com PG17 auditado |
| `supabase/.temp/project-ref` | ref remoto | importante para identificar o ambiente real |
| `supabase/.temp/rest-version` | versão REST | metadata |
| `supabase/.temp/storage-migration` | metadata de storage | metadata |
| `supabase/.temp/storage-version` | versão Storage | metadata |
| `supabase/config.toml` | configuração local do Supabase | **corrigir project_id, seed e política de auth** |
| `supabase/index.html` | shell da SPA | simples, mas dependências/CDN não totalmente reprodutíveis |
| `supabase/styles.css` | design system/estilo | visualmente organizado; precisa de testes reais de responsividade/acessibilidade |
| `supabase/app.min.js` | bundle executado | sintaxe OK; deveria ser produto de build |
| `supabase/fauna-fonte_privado.html` | fonte JSX incorporado | funcional, mas arquiteturalmente monolítico e dependente de Babel CDN |

---

# APÊNDICE B — estado remoto de funções `app_*`

As 71 funções chamadas pelo frontend foram encontradas no Supabase remoto com assinatura compatível, incluindo:

```text
app_accept_nda
app_accept_terms_v2
app_account_status
app_achievements_to_claim
app_admin_find_player
app_admin_grant_coins
app_admin_list_feedback
app_admin_list_photos
app_admin_overview
app_admin_set_feedback_status
app_admin_set_photo_focus
app_admin_set_photo_status
app_alpha_status
app_answer_quiz
app_burn_card
app_buy_cosmetic
app_buy_listing
app_buy_pack
app_cancel_listing
app_cancel_trade
app_checkin
app_checkin_status
app_claim_achievement
app_claim_all_achievements
app_claim_alpha_welcome
app_claim_mission
app_create_trade_by_name
app_extra_pack_price
app_family_children
app_family_create_invite
app_family_redeem_invite
app_family_set_control
app_family_unlink
app_finish_quiz
app_get_session_questions
app_is_admin
app_knowledge_status
app_legal_status_v2
app_list_card
app_match_play
app_match_question
app_match_start
app_match_status
app_missions_status
app_my_access
app_my_avatars
app_my_character
app_my_progress
app_my_summary
app_next_free_pack
app_open_pack
app_paste_card
app_paste_species_biome
app_player_binder
app_player_cards
app_public_profile
app_quiz_status
app_ranked_play
app_request_data_action
app_respond_trade
app_send_feedback
app_set_avatar
app_set_cards_public
app_set_character
app_set_for_trade
app_set_lang
app_set_ranked_team
app_set_showcase
app_set_username
app_start_quiz
app_transparency_totals
```

---

# APÊNDICE C — instrução condensada para outra IA

```text
STATUS DO PROJETO: ALPHA JOGÁVEL, NÃO HOMOLOGADO PARA PRODUÇÃO PÚBLICA.

NÃO REESCREVER O JOGO DO ZERO.

PRIMEIRO corrigir:
1. quiz: limitar p_num_questions no servidor;
2. quiz: impedir resposta duplicada;
3. quiz: reward deve derivar da primeira resposta persistida;
4. quiz: proteger limite diário contra concorrência;
5. ConsentGate: fail-closed;
6. Main/profile/NDA: fail-closed;
7. revisar as 5 views SECURITY DEFINER sinalizadas;
8. revisar grants e superfície de API.

DEPOIS:
9. check-in concurrency lock;
10. showcase concurrency lock;
11. ranked concurrency lock;
12. unique username lower-case;
13. registrar album consume no card_transactions;
14. decidir se ranked team é snapshot ou vínculo vivo;
15. criar baseline/schema + seed reproduzível;
16. corrigir drift de config project_id;
17. build/lint/test/CI;
18. só depois refatorar o monólito frontend.

REGRA DE OURO:
A UI nunca é autoridade. O Postgres é a autoridade para propriedade, moeda, recompensa, autorização e estado de jogo.

REGRA DE CONCORRÊNCIA:
Toda operação “uma vez por dia”, “máximo N”, “uma recompensa”, “compra única”, “troca única” ou transferência de ativo deve ser segura contra duas requisições simultâneas.

REGRA DE ERRO:
Erro de backend nunca deve ser convertido em sucesso, resposta errada, fim de partida, consentimento aceito ou estado persistido no cliente.

REGRA DE MIGRATION:
Não editar migrations aplicadas. Toda mudança nova em migration nova. Validar em banco vazio quando o baseline estiver corrigido.
```
