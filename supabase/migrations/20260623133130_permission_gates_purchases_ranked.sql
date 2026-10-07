create or replace function public.app_child_allowed(p_flag text)
 returns boolean language sql security definer set search_path to 'public'
as $$
  select case
    when not exists (select 1 from profiles where id = auth.uid() and guardian_id is not null) then true
    else coalesce((
      select case p_flag
        when 'allow_purchases' then allow_purchases
        when 'allow_trades'    then allow_trades
        when 'allow_ranked'    then allow_ranked
        when 'allow_social'    then allow_social
        else false end
      from parental_controls where child_id = auth.uid()), false)
  end;
$$;
revoke all on function public.app_child_allowed(text) from public, anon, authenticated;

do $do$
declare
  rec record; v_src text; v_new text; v_guard text;
begin
  for rec in
    select * from (values
      ('public.app_buy_pack()',      'if auth.uid() is null then raise exception ''Usuario nao autenticado''; end if;', 'allow_purchases', 'Compras precisam da autorizacao do seu responsavel'),
      ('public.app_buy_listing(uuid)','if auth.uid() is null then raise exception ''Usuario nao autenticado''; end if;', 'allow_purchases', 'Compras precisam da autorizacao do seu responsavel'),
      ('public.app_buy_cosmetic(text)','if v_uid is null then raise exception ''nao autenticado''; end if;',            'allow_purchases', 'Compras precisam da autorizacao do seu responsavel'),
      ('public.app_ranked_play()',   'if v_me is null then raise exception ''nao autenticado''; end if;',               'allow_ranked',    'A ranqueada precisa da autorizacao do seu responsavel')
    ) as t(sig, anchor, flag, msg)
  loop
    v_src := pg_get_functiondef(rec.sig::regprocedure);
    if position('app_child_allowed' in v_src) > 0 then continue; end if;
    v_guard := rec.anchor || chr(10) ||
               '    if not app_child_allowed(''' || rec.flag || ''') then raise exception ''' || rec.msg || '''; end if;';
    v_new := replace(v_src, rec.anchor, v_guard);
    if v_new = v_src then raise exception 'ancora nao encontrada em %', rec.sig; end if;
    execute v_new;
  end loop;
end $do$;;
