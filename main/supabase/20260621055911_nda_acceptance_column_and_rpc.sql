alter table public.profiles add column if not exists nda_accepted_at timestamptz;

create or replace function public.app_accept_nda()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  update profiles set nda_accepted_at = now() where id = auth.uid();
end;
$function$;

revoke all on function public.app_accept_nda() from anon, public;
grant execute on function public.app_accept_nda() to authenticated;;
