-- Pontuacao de conhecimento (sobe e desce, piso 0)
alter table profiles add column if not exists knowledge_rank integer not null default 0;

-- Faixa a partir do ranqueamento
create or replace function public.knowledge_tier(p_rank integer)
returns text language sql immutable as $$
  select case
    when p_rank >= 2000 then 'mestre'
    when p_rank >= 1000 then 'especialista'
    when p_rank >= 450  then 'conhecedor'
    when p_rank >= 150  then 'aprendiz'
    else 'iniciante'
  end;
$$;

-- Dificuldades liberadas por ranqueamento
create or replace function public.knowledge_allowed_difficulties(p_rank integer)
returns text[] language sql immutable as $$
  select case
    when p_rank >= 1000 then array['dificil','extremo']
    when p_rank >= 450  then array['media','dificil']
    when p_rank >= 150  then array['facil','media']
    else array['facil']
  end;
$$;

-- Status do conhecimento para a tela
create or replace function public.app_knowledge_status()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); v_rank int; v_floor int; v_next int;
begin
  if v_uid is null then raise exception 'Usuario nao autenticado'; end if;
  select coalesce(knowledge_rank,0) into v_rank from profiles where id = v_uid;
  v_rank := coalesce(v_rank,0);
  v_floor := case
    when v_rank >= 2000 then 2000 when v_rank >= 1000 then 1000
    when v_rank >= 450 then 450 when v_rank >= 150 then 150 else 0 end;
  v_next := case
    when v_rank >= 2000 then null when v_rank >= 1000 then 2000
    when v_rank >= 450 then 1000 when v_rank >= 150 then 450 else 150 end;
  return jsonb_build_object(
    'rank', v_rank,
    'tier', knowledge_tier(v_rank),
    'tier_label', case knowledge_tier(v_rank)
        when 'mestre' then 'Mestre' when 'especialista' then 'Especialista'
        when 'conhecedor' then 'Conhecedor' when 'aprendiz' then 'Aprendiz'
        else 'Iniciante' end,
    'allowed', to_jsonb(knowledge_allowed_difficulties(v_rank)),
    'floor', v_floor,
    'next_at', v_next
  );
end; $$;

grant execute on function public.app_knowledge_status() to authenticated;
grant execute on function public.knowledge_tier(integer) to authenticated;
grant execute on function public.knowledge_allowed_difficulties(integer) to authenticated;;
