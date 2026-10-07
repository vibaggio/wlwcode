# WildLens — Modelo de Ameaça

**Artefato vivo.** Atualize quando um novo vetor for descoberto.

---

## 1. Ativos a proteger

| Ativo | Impacto se comprometido |
|---|---|
| Saldo de moeda (`profiles.soft_currency`) | Inflação econômica, colapso do mercado |
| Propriedade de cartas (`card_instances`) | Perda de ativos, fraudes em trades |
| Ledger (`currency_ledger`, `card_transactions`) | Perda de auditabilidade |
| Consentimento legal (`legal_acceptances`) | Exposição jurídica (LGPD/COPPA) |
| NDA (`profiles.nda_accepted_at`) | Exposição de conteúdo privado |
| Permissões parentais (`parental_controls`) | Menores expostos a compras/ranked |
| Credenciais (`auth.users`, tokens) | Takeover de conta |
| PII de fotógrafos | Vazamento de dados pessoais |

---

## 2. Atores de ameaça

| Ator | Capacidade | Objetivo | Mitigação prioritária |
|---|---|---|---|
| Curioso com DevTools | Lê bundle, modifica requests | Ganhar moeda, desbloquear conteúdo | Server-authoritative |
| Jogador com `curl` + JWT | Chama RPCs livremente | Farmar quiz, duplicar recompensa | Locks + validação server-side |
| Criador de contas em massa | Signup automatizado | Abusar de welcome bonus | Rate limit + lock em claim |
| Admin comprometido | `service_role` ou conta admin | Conceder moeda ilimitada | Audit log + reautenticação |
| Vazamento de `service_role` | Bypassa RLS e RPCs | Controle total | Nunca expor + rotação |
| Competidor malicioso | Manipula mercado | Inflar preços, launder | Locks + ledger + detecção |
| Script kiddie | Copia ataques conhecidos | Ganhar vantagem | RLS + grants restritos |

**Regra derivada:** nenhuma proteção de RLS, constraint ou advisory lock
protege contra `service_role`. A única mitigação é **não expor** e **detectar**.

---

## 3. Vetores conhecidos

### 3.1. Quiz — parâmetro adulterado
- **Vetor:** `app_start_quiz(100)` → recompensa proporcional.
- **Mitigação:** servidor exige `p_num_questions = 5`.
- **Status:** P0.

### 3.2. Quiz — resposta reescrita
- **Vetor:** responder errado, receber `correct_option_id`, reenviar correto.
- **Mitigação:** `selected_option_id` imutável após persistido.
- **Status:** P0.

### 3.3. Quiz — tempo fraudulento
- **Vetor:** `p_time_taken = 0` em todas as respostas.
- **Mitigação:** servidor usa `answered_at - session_started_at`.
- **Status:** P0.

### 3.4. Quiz — limite diário por concorrência
- **Vetor:** duas abas chamam `app_start_quiz` no limite.
- **Mitigação:** advisory lock por usuário.
- **Status:** P0.

### 3.5. Gates fail-open
- **Vetor:** erro de rede em `app_legal_status_v2` → app libera.
- **Mitigação:** máquina de estados explícita; erro = bloqueio.
- **Status:** P0.

### 3.6. Views privilegiadas
- **Vetor:** view `SECURITY DEFINER` exposta na Data API.
- **Mitigação:** `security_invoker` + RLS, ou RPC mínima.
- **Status:** P1.

### 3.7. Concorrência em recompensas
- **Vetor:** duplo clique em check-in, claim_mission, claim_achievement,
  claim_alpha_welcome, perfect_pack.
- **Mitigação:** advisory lock + unique constraint onde aplicável.
- **Status:** P1.

### 3.8. Username case-insensitive
- **Vetor:** `Alice` e `alice` coexistem; impersonação.
- **Mitigação:** unique index `lower(trim(username))`.
- **Status:** P1.

### 3.9. Vazamento de `service_role`
- **Vetor:** chave exposta no bundle, em log, em repo público.
- **Mitigação:** grep no CI, rotação de chave, secrets fora do repo.
- **Status:** P0 (verificar ausência).

### 3.10. Admin sem audit log
- **Vetor:** admin concede moeda e não deixa rastro.
- **Mitigação:** `admin_audit_log` + inserção obrigatória.
- **Status:** P1.

### 3.11. `app_request_data_action` (LGPD/GDPR)
- **Vetor:** spam de exportação; vazamento por bug de `auth.uid()`.
- **Mitigação:** advisory lock, rate limit, auditoria.
- **Status:** P1.

### 3.12. Ausência de observabilidade
- **Vetor:** ataque em andamento não é detectado.
- **Mitigação:** `security_events` + métricas de outlier.
- **Status:** P1.

---

## 4. O que NÃO protege

- `disabled` em botão — não protege contra `curl`.
- Validação em React — não protege contra chamada direta à RPC.
- RLS sozinho — não protege contra `service_role`.
- Advisory lock sozinho — não protege contra `service_role`.
- `if exists(...)` antes de `INSERT` — corrida entre o `if` e o `INSERT`.
- Confiar em `p_time_taken`, `p_num_questions`, `p_user_id` do cliente.

---

## 5. Detecção

Eventos a registrar em `security_events`:

- `app_start_quiz` com `p_num_questions <> 5`;
- `app_answer_quiz` segunda vez na mesma questão;
- `app_finish_quiz` com sessão alheia;
- `app_checkin` rejeitado por duplicidade;
- `unique_violation` em `app_set_username`;
- rejeição por `app_child_allowed()`;
- `app_admin_*` executado;
- `app_request_data_action` chamado.

Métricas a monitorar:

- `quiz_sessions per user per day` (outlier = farm);
- taxa de rejeição em `app_answer_quiz` (indica probing);
- `currency_ledger` crescendo mais rápido que o esperado;
- picos de `unique_violation` em username.

---

## 6. Revisão

Este documento é revisado a cada:
- descoberta de novo vetor;
- mudança arquitetural significativa;
- incidente de segurança;
- ciclo de Security Advisor do Supabase.