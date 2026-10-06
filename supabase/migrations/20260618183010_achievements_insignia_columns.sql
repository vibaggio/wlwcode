alter table achievements add column if not exists is_insignia boolean not null default false;
alter table achievements add column if not exists insignia_icon text;
alter table achievements add column if not exists insignia_tier text;
alter table achievements add column if not exists reward_avatar_key text;;
