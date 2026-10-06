-- Otimizacao de performance: evita reavaliar auth.uid() linha a linha.
-- Nao muda o que cada politica permite, so como o Postgres executa a checagem.

alter policy family_codes_guardian_delete on public.family_link_codes
  using (guardian_id = (select auth.uid()));

alter policy family_codes_guardian_select on public.family_link_codes
  using (guardian_id = (select auth.uid()));

alter policy parental_controls_child_select on public.parental_controls
  using (child_id = (select auth.uid()));

alter policy parental_controls_guardian_select on public.parental_controls
  using (exists (select 1 from profiles c where c.id = parental_controls.child_id and c.guardian_id = (select auth.uid())));

alter policy parental_controls_guardian_update on public.parental_controls
  using (exists (select 1 from profiles c where c.id = parental_controls.child_id and c.guardian_id = (select auth.uid())))
  with check (exists (select 1 from profiles c where c.id = parental_controls.child_id and c.guardian_id = (select auth.uid())));;
