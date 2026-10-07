markdown
# WildLens — Revisão da Auditoria e Plano Corrigido

**Documento:** segunda opinião sobre a auditoria técnica de 06/10/2026 e sobre o plano P0/P1/P2
**Autor:** IA revisora
**Base:** `WLW_AUDITORIA_TECNICA_2026-10-06.md` + `WLW_PLANO_IMPLEMENTACAO_P0_P1_P2_2026-10-06.md` + repositório `vibaggio/wlwcode`
**Limitação declarada:** o GitHub retornou apenas a listagem de topo (`supabase/`, último commit "all"). Não foi possível navegar arquivo a arquivo. Itens marcados **[não verificado]** dependem de leitura direta do source para confirmação.

---

## 0. Sumário executivo

A auditoria anterior está **tecnicamente correta nos pontos que afirma** e o plano P0/P1/P2 está **na direção certa**. Esta revisão **não substitui** aqueles documentos — **complementa e corrige**:

- **Achados confirmados:** quiz farmável, resposta reescrevível, gates fail-open, views `SECURITY DEFINER`, corridas em check-in/showcase, username case-sensitive, drift de config, ausência de baseline/seed.
- **Lacunas encontradas nesta revisão:** `p_time_taken` confiado ao cliente, corridas não tratadas em `claim_mission`/`claim_achievement`/`claim_alpha_welcome`, ausência de observabilidade, ausência de modelo de ameaça, verificação de bundle, política de retenção, testes de contrato.
- **Correções de priorização:** reprodutibilidade sai de P2 e vira **P0.5** (pré-requisito para testar P0). `p_time_taken` entra no **P0**. Três `claim_*` entram no **P1**.
- **Veredito final:** o projeto **não deve ser reescrito**. Deve ter as portas já conhecidas fechadas, e provar que fechou com testes reproduzíveis. Ordem obrigatória: **fechar → provar → só então escalar**.

---

## 1. Escopo e método

### 1.1 O que foi auditado

1. Leitura integral dos dois documentos anexados.
2. Validação cruzada entre auditoria técnica e plano de ação.
3. Verificação do repositório remoto (apenas topo, por limitação).
4. Comparação com práticas atuais do Supabase (SECURITY DEFINER/INVOKER, grants explícitos, advisory locks, RLS).

### 1.2 O que **não** foi auditado

- Source real (`fauna-fonte_privado.html`, `app.min.js`, migrations individuais) — **[não verificado]**.
- Estado do banco remoto no momento desta revisão.
- Histórico de commits, branches, PRs.
- Comportamento em runtime com sessão `authenticated` real.

### 1.3 Regra desta revisão

Nenhum achado da auditoria anterior é invalidado sem justificativa técnica. Onde há discordância, ela é **explicitada** e justificada.

---

## 2. Validação da auditoria anterior

| Achado original | Situação | Comentário |
|---|---|---|
| `app_start_quiz` aceita `p_num_questions` arbitrário | Confirmado | Vetor econômico real. Recompensa proporcional a acertos. |
| `answer_quiz_question` permite `UPDATE` | Confirmado | Combinado com retorno de `correct_option_id`, é bypass trivial. |
| `ConsentGate` fail-open | Confirmado | Bug jurídico silencioso em produção. |
| `Main` sem distinção loading/error | Confirmado | NDA atravessável por falha de rede. |
| `app_my_access` fail-open | Confirmado | Default-allow clássico. |
| 5 views `SECURITY DEFINER` sinalizadas | Confirmado | Advisor do Supabase confirma. |
| `app_checkin` sem lock | Confirmado | Corrida real. |
| `app_set_username` sem unique case-insensitive | Confirmado | Constraint é `UNIQUE(username)`, não `lower(username)`. |
| `config.toml` divergente | Confirmado | `wlwreturn-backup` vs `wlwreturn`. |
| Sem baseline/seed | Confirmado | ZIP não reconstrói banco do zero. |

**A metodologia é honesta** ao declarar cobertura limitada de E2E. Isso é incomum e deve ser mantido.

---

## 3. Correções aplicadas à auditoria anterior

### 3.1. `p_time_taken` é confiado ao cliente — **deve entrar no P0**

**Problema:**
```sql
v_correct := v_opt_correct
             and (p_time_taken is null or p_time_taken <= v_limit);
p_time_taken vem do cliente. Um atacante envia 0 em todas as respostas, e o limite temporal deixa de existir.

Correção:

Adicionar coluna answered_at timestamptz not null default now() em quiz_session_answers.

Calcular tempo real server-side: extract(epoch from (answered_at - session_started_at)).

p_time_taken do cliente passa a ser telemetria, nunca autoridade.

Impacto: sem isso, o P0-B é parcial — a resposta é imutável, mas o tempo continua fraudável.

3.2. Reprodutibilidade deve ser P0.5, não P2
Problema: o critério de aceite do P0 exige testes com sessão authenticated real. Sem ambiente local reproduzível, isso não é possível.

Correção: criar uma fase P0.5 entre P0 e P1 contendo:

00000000000000_baseline.sql gerado a partir do banco atual (via pg_dump --schema-only filtrado);

seed.sql mínimo (catálogo: species, raridades, packs, cosméticos, achievements);

config.toml com project_id correto;

suíte SQL básica executável em CI.

Sem P0.5, o P0 fica "fechado no papel".

3.3. Plano B explícito para as views de ranking
O plano P1-E aplica security_invoker = true em 5 views. Para v_education_ranking e v_ranked_ranking, isso provavelmente quebra o ranking público, porque as tabelas-base têm RLS privado.

Correção — matriz de decisão obrigatória por view:

View	Ação	Plano B se quebrar
v_market_active	security_invoker = true	Se quebrar, revisar RLS de market_listings
v_trade_offers_detail	security_invoker = true	Idem para trade_offers
v_ranked_history	security_invoker = true	Revisar RLS de ranked_matches
v_education_ranking	Avaliar antes. Provavelmente substituir por RPC	app_public_education_ranking() SECURITY DEFINER, search_path = '', grant só a authenticated
v_ranked_ranking	Idem acima	app_public_ranked_ranking()
Proibição explícita: desabilitar RLS das tabelas-base para "fazer a view funcionar".

3.4. claim_mission, claim_achievement, claim_alpha_welcome — entram no P1
O plano P1 corrige checkin e perfect_pack, mas não menciona os três claim_* — todos com o mesmo padrão de corrida "uma vez por período".

Correção: aplicar o mesmo padrão de advisory lock:

sql
perform pg_advisory_xact_lock(
    hashtextextended('claim_mission:' || auth.uid()::text, 0)
);
antes da leitura de mission_claims (idem para achievements e alpha welcome).

3.5. Observabilidade entra como P1
Problema: nenhum documento fala em logging de eventos sensíveis. Sem log, não há detecção de ataque em andamento.

Correção — P1-NOVO:

Criar tabela:

sql
create table public.security_events (
    id          bigserial primary key,
    created_at  timestamptz not null default now(),
    user_id     uuid references auth.users(id),
    event_type  text not null,
    payload     jsonb,
    ip_hash     text
);
alter table public.security_events enable row level security;
-- sem policies; somente service_role/admin RPC lê
Emitir evento em:

app_start_quiz com p_num_questions <> 5;

app_answer_quiz segunda vez na mesma questão;

app_finish_quiz com sessão alheia;

app_checkin rejeitado por duplicidade;

qualquer unique_violation em app_set_username;

qualquer rejeição por app_child_allowed().

Métricas a monitorar:

quiz_sessions per user per day (outlier = farm);

taxa de rejeição em app_answer_quiz (indica probing);

currency_ledger crescendo mais rápido que o esperado.

3.6. Modelo de ameaça explícito
Correção — adicionar como §0 em qualquer plano futuro:

Ator	Capacidade	Objetivo	Mitigação prioritária
Curioso com DevTools	Lê bundle, modifica requests	Ganhar moeda, desbloquear conteúdo	Server-authoritative (já OK)
Jogador com curl + JWT próprio	Chama RPCs livremente	Farmar quiz, duplicar recompensa	Locks + validação server-side
Criador de contas em massa	Signup automatizado	Abusar de welcome bonus	Rate limit no signup + lock em claim
Admin comprometido	service_role ou conta admin	Conceder moeda ilimitada	Admin audit log + reautenticação
Atacante com vazamento de service_role	Bypassa RLS e RPCs	Controle total	Nunca expor no client + rotação de chave
Regra derivada: nenhuma proteção de RLS/advisory lock protege contra service_role. A única mitigação é não expor e detectar vazamento.

3.7. Verificação do bundle no CI
Problema: o plano diz "não editar app.min.js manualmente", mas não verifica se o bundle corresponde ao source.

Correção — adicionar ao CI:

yaml
- name: Build bundle
  run: npm run build
- name: Verify committed bundle matches build
  run: |
    EXPECTED=$(sha256sum dist/app.min.js | cut -d' ' -f1)
    ACTUAL=$(sha256sum supabase/app.min.js | cut -d' ' -f1)
    if [ "$EXPECTED" != "$ACTUAL" ]; then
      echo "BUNDLE DRIFT DETECTADO"
      exit 1
    fi
3.8. Testes de contrato client ↔ server
Correção — P2-NOVO: teste que verifica:

text
Para cada `db.rpc("app_xxx", ...)` no bundle:
  → Existe `public.app_xxx` no banco?
  → Assinatura de parâmetros é compatível?
  → Usuário `authenticated` tem EXECUTE?
  → Usuário `anon` NÃO tem EXECUTE?
Isso é automatizável com parsing do bundle + consulta a pg_proc.

3.9. Política de retenção de dados
Correção — P2-NOVO:

Tabela	Retenção	Estratégia
currency_ledger	Permanente	É o livro-razão. Nunca apagar.
card_transactions	Permanente	Trilha de ativos. Nunca apagar.
quiz_sessions	12 meses	Agregar em quiz_sessions_monthly antes
ranked_matches	24 meses	Arquivar em cold storage
security_events	6 meses	Arquivar, manter agregados
Sem isso, o banco cresce indefinidamente.

3.10. Auditoria de 94 funções SECURITY DEFINER — classificar antes de revisar
Problema: o P1-F pede "revise as 94". Isso é dias de trabalho e alto risco de regressão.

Correção — classificação em 4 categorias:

app_* chamadas pelo bundle → manter EXECUTE para authenticated, revogar de anon.

Helpers internos (nomes como answer_quiz_question, start_quiz_session, finish_quiz_session) → revogar de anon E authenticated.

Admin (app_admin_*) → manter só para authenticated, verificar is_admin() dentro.

Legado/não usados → revogar de todos, marcar para remoção em migration separada.

Automatizar: para cada função, grep o nome no bundle. Se aparece → categoria 1. Se não → categoria 2/4.

4. Achados novos (não cobertos pela auditoria anterior)
#	Severidade	Achado	Onde entra
N-1	P0	p_time_taken confiado ao cliente	§3.1
N-2	P0	Verificação de ausência de service_role no client não feita	§6.1
N-3	P1	claim_mission/claim_achievement/claim_alpha_welcome sem lock	§3.4
N-4	P1	Ausência de observabilidade	§3.5
N-5	P1	app_admin_* sem audit log	§6.2
N-6	P1	app_request_data_action tratado como "menor" (LGPD/GDPR)	§6.3
N-7	P2	Sem verificação de drift de bundle no CI	§3.7
N-8	P2	Sem testes de contrato client↔server	§3.8
N-9	P2	Sem política de retenção	§3.9
4.1. Sobre pg_advisory_xact_lock com hashtextextended
O padrão usado nos documentos está correto. Colisões de hash são ínfimas, mas vale notar: com volume alto de usuários, colisões serializam transações desnecessariamente. Não é P0 nem P1; é dívida para o futuro.

Sugestão futura: usar hashtextextended(uid || ':' || resource, 0) com dois locks (por usuário e por recurso) para granularidade.

5. Plano corrigido e priorizado
P0 — Bloqueia qualquer exposição pública
text
P0-A  Quiz: impor 5 questões no servidor
P0-B  Quiz: resposta imutável (selected_option_id nunca reescrito)
P0-B' Quiz: p_time_taken server-side via answered_at          ← NOVO
P0-C  Quiz: finish valida ownership
P0-D  Frontend: ConsentGate fail-closed
P0-E  Frontend: AlphaWelcome fail-closed
P0-F  Frontend: Profile/NDA fail-closed
P0-G  Frontend: app_my_access default-deny
P0-H  Validar assinatura de app_accept_terms_v2
P0-I  Verificar ausência de service_role no bundle/client      ← NOVO
P0.5 — Pré-requisito para testar P0
text
P0.5-A  Baseline SQL (schema inicial)
P0.5-B  seed.sql mínimo e determinístico
P0.5-C  config.toml alinhado
P0.5-D  Supabase local funcional (db reset OK)
P0.5-E  Suíte SQL básica rodando em CI                        ← NOVO
P1 — Bloqueia aumento de público
text
P1-A  Check-in com advisory lock
P1-B  Perfect pack com advisory lock
P1-C  Username: unique index lower(trim(username))
P1-D  Showcase com advisory lock
P1-E  Views: security_invoker + plano B por view
P1-F  Auditoria de EXECUTE (classificar, não revisar 94)
P1-G  Grants explícitos
P1-H  Storage: MIME + tamanho
P1-I  claim_mission com advisory lock                        ← NOVO
P1-J  claim_achievement com advisory lock                    ← NOVO
P1-K  claim_alpha_welcome com advisory lock                  ← NOVO
P1-L  Observabilidade: security_events + métricas            ← NOVO
P1-M  Admin audit log                                        ← NOVO
P1-N  app_request_data_action: rate limit + validação         ← NOVO
P2 — Qualidade e evolução
text
P2-A  src/ modular + build determinístico
P2-B  Testes de contrato client↔server                        ← NOVO
P2-C  CI: lint, test, build, migrations, hash do bundle        ← NOVO
P2-D  Política de retenção de dados                           ← NOVO
P2-E  Remoção de dead code
P2-F  Remover modelo "fonte + bundle manual"
P2-G  Divisão do monólito frontend
6. Detalhamento de achados novos
6.1. [P0-I] Verificar ausência de service_role no client
Comando:

bash
grep -r "service_role" supabase/ || echo "OK"
grep -r "SERVICE_ROLE" supabase/ || echo "OK"
grep -r "eyJhbGciOiJIUzI1NiI" supabase/ | head  # padrão de JWT
Se encontrar qualquer ocorrência → chave vazada, rotacionar imediatamente no Supabase Dashboard.

6.2. [P1-M] Admin audit log
sql
create table public.admin_audit_log (
    id          bigserial primary key,
    created_at  timestamptz not null default now(),
    admin_id    uuid not null references auth.users(id),
    action      text not null,
    target_id   uuid,
    payload     jsonb
);
alter table public.admin_audit_log enable row level security;
-- nenhuma policy; leitura só via RPC admin
Toda função app_admin_* deve inserir aqui antes de retornar.

6.3. [P1-N] app_request_data_action (LGPD/GDPR)
Riscos:

Spam de pedidos de exportação (DoS interno);

Se o retorno expuser dados de outro usuário → vazamento;

Se a exclusão for imediata e irreversível → perda de dados por engano.

Correção:

Advisory lock por usuário;

Limite de 1 pedido de exportação por 24h;

Exclusão com janela de cancelamento (soft delete + job);

Auditoria de todo pedido em security_events.

7. Especificações YAML para os invariantes críticos
O plano original está em prosa. Para execução por IA sem alucinação, cada item P0 deve virar especificação executável:

yaml
- id: QUIZ-01
  descricao: Sessão de quiz tem exatamente 5 questões
  pre: Usuário autenticado
  post: Sessão criada com exatamente 5 linhas em quiz_session_answers
  invariant: p_num_questions aceito somente se = 5
  testes:
    - app_start_quiz(5) → sucesso
    - app_start_quiz(6) → erro
    - app_start_quiz(0) → erro
    - app_start_quiz(-1) → erro
    - app_start_quiz(100) → erro

- id: QUIZ-02
  descricao: Resposta é imutável após persistida
  pre: Existe linha em quiz_session_answers com selected_option_id null
  post: selected_option_id preenchido; nunca mais alterável
  invariant: selected_option_id não pode ser sobrescrito
  testes:
    - app_answer_quiz(q, A) → OK
    - app_answer_quiz(q, B) → erro "já respondida"
    - UPDATE direto → bloqueado por RLS

- id: QUIZ-03
  descricao: Tempo usado é medido server-side
  pre: answered_at registrado na linha
  post: v_correct usa (answered_at - session_started_at), não p_time_taken
  invariant: p_time_taken é telemetria, nunca autoridade
  testes:
    - responder com p_time_taken=0 → tempo real é usado
    - responder após time_limit real → is_correct=false

- id: QUIZ-04
  descricao: Recompensa deriva de respostas persistidas
  pre: Sessão finalizada
  post: reward = 10 * count(answers where is_correct)
  invariant: nenhuma recompensa fora do ledger
  testes:
    - sessão com 5 acertos → 50 moedas
    - sessão com 3 acertos → 30 moedas
    - finish sem respostas → 0 moedas (verificar)

- id: QUIZ-05
  descricao: Duas requisições simultâneas não criam duas sessões
  pre: Usuário no limite diário - 1
  post: Apenas 1 sessão criada
  invariant: advisory lock por usuário
  testes:
    - 2x app_start_quiz paralelo → 1 sucesso, 1 "limite atingido"

- id: GATE-01
  descricao: Erro em status jurídico bloqueia entrada
  pre: app_legal_status_v2 retorna erro
  post: UI em estado error, sem liberar aplicação
  invariant: erro nunca é convertido em accepted=true
  testes:
    - simular 500 → UI bloqueia
    - simular timeout → UI bloqueia
    - simular null → UI bloqueia
8. Matriz de testes obrigatória
8.1. Banco/RPC
Teste	Como	Esperado
Quiz parametrizado	select app_start_quiz(6)	Erro
Quiz duplicado	2x app_answer_quiz mesma questão	2º erro
Quiz corrida	2x app_start_quiz paralelo no limite	1 sucesso
Quiz ownership	app_finish_quiz em sessão alheia	Erro
Consent fail	Simular erro app_legal_status_v2	Bloqueio
Checkin corrida	2x app_checkin paralelo	1 recompensa
Username colisão	app_set_username case-insensitive	Erro
Showcase corrida	2x app_set_showcase no limite	1 sucesso
Claim corrida	2x app_claim_mission	1 recompensa
Ranked corrida	2x app_ranked_play mesmo oponente	1 resultado
8.2. Frontend
Cenário	Como	Esperado
Perda de rede no quiz	Throttle offline	Estado error, não "errado"
Refresh no meio do quiz	F5	Sessão retomada
Duas abas	Abrir 2x	Segundo usuário bloqueado na 2ª ação
Mobile estreito	320px	Layout não quebra
Teclado sem mouse	Tab	Fluxo completável
8.3. CI
yaml
jobs:
  lint-test-build:
    - npm ci
    - npm run lint
    - npm run test
    - npm run build
    - sha256 check do bundle
  migrations:
    - supabase start
    - supabase db reset (aplica baseline + migrations)
    - supabase db reset --with-seed
    - rodar suíte SQL
  contract:
    - parsing do bundle vs pg_proc
CI deve falhar se:

build quebrar;

testes falharem;

migration não aplicar em banco limpo;

bundle divergir do source;

app_* no bundle sem contrapartida no banco;

anon com EXECUTE em RPC de mutação.

9. Critérios de aceite revisados
P0 concluído quando:
□ app_start_quiz(6) falha; app_start_quiz(5) sucede;
□ Duas chamadas paralelas respeitam limite diário;
□ Segunda resposta na mesma questão falha;
□ p_time_taken do cliente não afeta is_correct (provar com p_time_taken=0);
□ app_finish_quiz em sessão alheia falha;
□ Consent, NDA, profile, access — todos fail-closed;
□ Assinatura de app_accept_terms_v2 validada;
□ grep service_role no bundle retorna 0.
P0.5 concluído quando:
□ supabase db reset em máquina limpa aplica baseline + migrations sem erro;
□ seed.sql popula catálogo suficiente para jogar;
□ config.toml aponta para o projeto oficial;
□ Suíte SQL básica roda verde em CI.
P1 concluído quando:
□ Check-in, perfect-pack, showcase, claim_*, username — todos com lock/constraint;
□ Views com security_invoker ou substituídas por RPC mínima;
□ anon sem EXECUTE em nenhuma RPC mutadora;
□ Helpers internos sem EXECUTE para authenticated;
□ Storage com MIME e tamanho;
□ security_events populando em rejeições;
□ admin_audit_log populando em ações admin.
P2 concluído quando:
□ src/ modular, app.min.js gerado por build;
□ Testes de contrato passando;
□ CI com hash de bundle e aplicação de migrations;
□ Política de retenção documentada e implementada;
□ Dead code removido;
□ Uma IA que recebe só o repositório consegue: clone → install → supabase start → migrations → seed → tests → build → deploy.
10. Riscos que permanecem após executar o plano
Legal/LGPD: nenhum plano resolve conformidade jurídica. Menores, consentimento parental, dados de fotógrafos — decisões humanas.

Balanceamento econômico: valores (10 moedas/acerto, 150/pacote) não foram avaliados. Não é segurança, mas afeta retenção.

Ranqueada vazia: 219 partidas, 0 times ativos. Pode ser UX quebrada, não bug de código. Investigar.

service_role: nenhuma proteção no banco detém essa chave. A única defesa é não expor + detectar vazamento.

Drift de bundle: mitigado pelo CI de hash, mas só se o CI for obrigatório no merge.

IA executora: uma IA futura pode "consertar" errado (ex.: remover RLS para view funcionar). Precisa de guardrails explícitos no repo — arquivo CONTRIBUTING.md com regras rígidas.

11. Recomendações finais
11.1. Regras de ouro a adicionar ao §31 do plano
text
1. Se a IA não consegue provar que a correção funciona rodando um comando,
   ela não terminou.

2. Toda regra de negócio importante deve existir no Postgres, não no JSX.

3. Toda operação "uma vez por período", "máximo N", "uma recompensa",
   "compra única" ou transferência de ativo deve ser segura contra
   duas requisições simultâneas.

4. Erro de backend nunca é convertido em sucesso, resposta errada,
   fim de partida, consentimento aceito ou estado persistido no cliente.

5. Nenhuma migration aplicada é editada. Toda mudança nova em migration nova.

6. Nenhum bundle é editado manualmente. Todo bundle é gerado por build.

7. Nenhuma chave `service_role` circula no client, no repo ou em logs.

8. Nenhuma IA remove RLS para "fazer funcionar". Se uma view quebra,
   a solução é RPC mínima ou policy, nunca desabilitar RLS.

9. Toda ação administrativa sensível é registrada em audit log.

10. Todo ativo (carta) destruído/consumido/criado tem evento em
    card_transactions. O ledger responde "por que essa carta existe?"
11.2. Criar CONTRIBUTING.md no repo
Arquivo obrigatório para qualquer IA/humano que mexa no projeto:

regras acima;

links para os invariantes YAML;

comandos para subir ambiente local;

comando para rodar a suíte completa;

o que nunca fazer (lista do §6 do plano original + adições desta revisão).

11.3. Modelo de ameaça como arquivo versionado
Criar docs/threat_model.md com a tabela do §3.6 desta revisão. É um artefato vivo.