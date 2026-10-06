# Próximos passos — WildLens

Ordem obrigatória. **Não inverta.**

---

## Hoje (30 min)

### 1. Criar os arquivos desta rodada no repositório

```bash
git checkout -b docs/auditoria-e-governanca

# Copie os arquivos para as posições:
#   CONTRIBUTING.md
#   docs/threat_model.md
#   docs/invariants/README.md
#   docs/invariants/P0.yaml
#   docs/PROXIMOS_PASSOS.md
#   .github/workflows/ci.yml
#   scripts/contract-test.mjs

git add .
git commit -m "docs: governança, threat model, invariantes P0 e CI"
git push origin docs/auditoria-e-governanca
```

### 2. Abrir PR e mergear

O CI vai falhar nesta primeira execução — é esperado.
- Job `frontend` falha porque `package.json` ainda não existe.
- Job `contract` falha pelo mesmo motivo.
- Job `database` pode falhar porque `supabase/tests/` está vazio.

**Ação:** abrir issues separadas para cada falha e ir resolvendo em ordem.

### 3. Verificar `service_role` (5 min)

```bash
grep -r "service_role" supabase/ || echo "OK: nada encontrado"
grep -rE "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" supabase/ | head
```

Se encontrar qualquer ocorrência com `service_role`, **rotacione a chave
imediatamente** no Supabase Dashboard → Settings → API.

---

## Semana 1 — P0 no banco

Ordem de execução (uma migration por item):

1. `P0-A` — `app_start_quiz` exige 5.
2. `P0-B` — resposta imutável.
3. `P0-B'` — `answered_at` server-side.
4. `P0-C` — ownership no finish.
5. Testar cada uma com `docs/invariants/P0.yaml` antes de seguir.

Cada migration:
- vai em `supabase/migrations/`;
- passa por `supabase db reset`;
- tem teste em `supabase/tests/`;
- é acompanhada de PR com saída real dos testes.

---

## Semana 1 — P0 no frontend

- `P0-D` — `ConsentGate` fail-closed.
- `P0-E` — `AlphaWelcome` fail-closed.
- `P0-F` — `Main`/NDA fail-closed.
- `P0-G` — `app_my_access` default-deny.
- `P0-H` — validar `app_accept_terms_v2`.
- `P0-I` — verificar ausência de `service_role` (feito acima).

**Antes de P0-D**, o source ainda é `fauna-fonte_privado.html`.
Edite lá — mas **só depois de P0.5** comece a migrar para `src/`.

---

## Semana 2 — P0.5 (reprodutibilidade)

**Pré-requisito para testar P0 de verdade.**

1. Gerar baseline a partir do banco remoto:
   ```bash
   supabase db dump --schema public > supabase/migrations/00000000000000_baseline.sql
   ```
2. Criar `seed.sql` mínimo (catálogo, sem PII, sem dados reais).
3. Corrigir `config.toml`: `project_id = "wlwreturn"` (não `-backup`).
4. Criar `supabase/tests/` com a suíte de invariantes.
5. Rodar `supabase db reset --with-seed` em máquina limpa e confirmar.

Quando P0.5 estiver feito, o CI fica verde até o job `database`.

---

## Semana 3 — P1

Só comece P1 quando:

- [ ] Todos os testes de P0 passam com sessão `authenticated` real.
- [ ] CI está verde até `database`.
- [ ] Nenhum `service_role` no repo.

Ordem P1 (uma migration por item):

1. Lock em `app_checkin`.
2. Lock em `app_claim_mission`.
3. Lock em `app_claim_achievement`.
4. Lock em `app_claim_alpha_welcome`.
5. Lock em `app_set_showcase`.
6. Lock em perfect-pack.
7. Unique index `lower(trim(username))`.
8. Views — aplicar `security_invoker` com plano B.
9. Grants explícitos.
10. `security_events` + métricas.
11. `admin_audit_log`.
12. Storage: MIME + tamanho.

Cada item: migration + teste + PR com prova.

---

## Semana 4+ — P2

Só depois de P1 estável:

1. `src/` modular + build determinístico.
2. Testes de contrato client↔server.
3. CI completo verde.
4. Política de retenção.
5. Remoção de dead code.
6. Remover modelo "fonte + bundle manual".

---

## Como validar que terminou

Um item só está pronto quando:

- [ ] Existe migration versionada.
- [ ] Existe teste em `supabase/tests/` que **falha antes** e **passa depois**.
- [ ] A saída real do teste está colada no PR.
- [ ] `supabase db reset --with-seed` funciona em máquina limpa.
- [ ] CI está verde.
- [ ] O item correspondente em `docs/invariants/P0.yaml` está com todos os testes passando.

---

## O que fazer se uma IA executora travar

1. Pedir para ela colar a saída **real** do último comando.
2. Se ela não testou, mandar testar antes de continuar.
3. Se ela propôs remover RLS, rejeitar.
4. Se ela propôs `service_role` no client, rejeitar.
5. Se ela disse "feito" sem prova, pedir prova.
6. Se ela editou migration aplicada, reverter e refazer.

**Regra:** *"Se você não consegue provar que funciona, você não terminou."*