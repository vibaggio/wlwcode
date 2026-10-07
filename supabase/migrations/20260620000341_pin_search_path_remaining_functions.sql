-- Fixa search_path nas funcoes restantes (todas referenciam objetos do schema public)
alter function public.buy_listing(uuid, uuid) set search_path = public;
alter function public.generate_card(uuid, uuid, uuid) set search_path = public;
alter function public.knowledge_allowed_difficulties(integer) set search_path = public;
alter function public.knowledge_tier(integer) set search_path = public;
alter function public.open_basic_pack(uuid) set search_path = public;
alter function public.rarity_from_float(numeric) set search_path = public;
alter function public.reset_for_trade_on_owner_change() set search_path = public;;
