alter table public.photos
  add column if not exists focal_x smallint not null default 50,
  add column if not exists focal_y smallint not null default 50;

alter table public.photos
  add constraint photos_focal_x_range check (focal_x between 0 and 100),
  add constraint photos_focal_y_range check (focal_y between 0 and 100);

comment on column public.photos.focal_x is 'Ponto focal horizontal (0 a 100) para object-position na carta. 50 = centro.';
comment on column public.photos.focal_y is 'Ponto focal vertical (0 a 100) para object-position na carta. 50 = centro.';;
