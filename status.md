# STATUS — WildLens

**Última atualização:** 2026-10-06
**Atualizado por:** <seu nome>

## Onde estamos

### ✅ Concluído

- [x] P0 do quiz no banco (migration `20261006000100_harden_quiz_integrity.sql` aplicada)
  - `app_start_quiz` exige 5 questões
  - resposta imutável (`selected_option_id` + `answered_at`)
  - tempo medido server-side (`clock_timestamp()`)
  - ownership no `app_finish_quiz`
  - 72 testes passaram (rodados pela IA no banco real, saída registrada em `docs/evidencias/`)

### ⏳ Não iniciado

- [ ] P0 frontend: gates fail-closed (`ConsentGate`, `AlphaWelcome`, `Main`, `app_my_access`)
- [ ] P0.5: baseline + `seed.sql` + ambiente local reproduzível
- [ ] P1: locks em checkin, claim_mission, claim_achievement, claim_alpha_welcome, showcase
- [ ] P1: unique index `lower(trim(username))`
- [ ] P1: views `security_invoker` com plano B
- [ ] P1: observabilidade (`security_events`)
- [ ] P1: admin audit log
- [ ] P2: `src/` modular + build determinístico

## ⚠️ Avisos importantes

1. **NÃO ESTÁ PRONTO PARA PÚBLICO.** Os gates do frontend ainda são fail-open.
   O jogo pode ser acessado sem consentimento em caso de falha de rede.
2. **Existe uma migration órfã** (`20261006150128`) no banco remoto que
   não está no repo. Foi aplicada por IA sem autorização. Não remova,
   não se preocupe — a nova (`...000100`) já sobrescreveu o que importa.
3. **O `ci.yml` está com bug conhecido** (comando `supabase db execute`).
   Correção pendente de commit.

## 📋 Regras para a próxima IA

Leia `CONTRIBUTING.md` **inteiro** antes de qualquer coisa. Em especial:

- NÃO aplicar migration no banco remoto. Só escrever arquivos.
- NÃO tocar em RLS.
- NÃO remover EXECUTE a `anon` que já existe.
- NÃO editar `app.min.js` manualmente.
- NÃO usar `service_role` em lugar nenhum.
- Se não conseguiu testar, DIGA.

## 🔗 Onde estão as coisas

- `docs/PROXIMOS_PASSOS.md` — ordem oficial do roadmap
- `docs/invariants/P0.yaml` — especificação executável dos invariantes P0
- `docs/threat_model.md` — modelo de ameaça
- `docs/evidencias/` — onde salvar saídas reais de testes futuros

## Drift de migrations (conhecido, aceito temporariamente)

- `20261006150128` está registrada na tabela `schema_migrations` do Supabase
  (aplicada por IA em sessão anterior, sem autorização, não está no repo).
- `20261006000100` NÃO está registrada, porque foi aplicada via SQL Editor
  (que não registra migrations).
- O estado real do banco está correto (funções + colunas aplicadas).
- Ações: NÃO rodar `supabase db push` até reconciliar.
- Reconciliar em P0.5 (baseline).