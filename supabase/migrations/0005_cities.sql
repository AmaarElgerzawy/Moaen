-- Moaen (معاين) — 0005_cities.sql
-- Canonical Egyptian city list (P10).
--
-- The job board matches `car_inspections.city` against the inspector's
-- `users.location_city` by `lower(btrim(...))` equality. Until now both were
-- free text, so "Cairo" typed by a buyer and "القاهرة" typed by an inspector
-- were different strings and the request silently vanished from every board.
-- The only fix that actually holds is to stop letting either side type a city:
-- both pick from this list, so an exact match is guaranteed.
--
-- The list is read-only through the client API (SELECT only, for any role —
-- including `anon`, because the city picker is on the *sign-up* form, which
-- runs before a session exists). This is the one deliberate exception to the
-- project rule that `anon` reads nothing: city names are public reference data,
-- the way a country list on any registration form is. Every marketplace table
-- still reads nothing to `anon`.
--
-- `city` and `location_city` remain free text columns with no CHECK against
-- this table. Locking them to canonical values would need a migration of all
-- existing rows and a foreign key on a column clients can already write, and it
-- would not improve matching — the app always writes a canonical value now.

create table public.cities (
  id      smallserial primary key,
  name_ar text not null unique,
  name_en text not null unique
);

insert into public.cities (name_ar, name_en) values
  ('6 أكتوبر',        '6 October City'),
  ('أسيوط',           'Asyut'),
  ('أسوان',           'Aswan'),
  ('الإسماعيلية',     'Ismailia'),
  ('الإسكندرية',      'Alexandria'),
  ('الأقصر',          'Luxor'),
  ('الخارجة',         'El Kharga'),
  ('الغردقة',         'Hurghada'),
  ('الزقازيق',        'Zagazig'),
  ('السويس',          'Suez'),
  ('الشروق',          'El Shorouk'),
  ('العاشر من رمضان', '10th of Ramadan City'),
  ('العريش',          'Arish'),
  ('الطور',           'El Tor'),
  ('الفيوم',          'Faiyum'),
  ('القاهرة',         'Cairo'),
  ('المحلة الكبرى',   'El Mahalla El Kubra'),
  ('المنصورة',        'Mansoura'),
  ('المنيا',          'Minya'),
  ('بني سويف',        'Beni Suef'),
  ('بنها',            'Banha'),
  ('بورسعيد',         'Port Said'),
  ('دمياط',           'Damietta'),
  ('دمنهور',          'Damanhur'),
  ('رأس سدر',         'Ras Sedr'),
  ('سوهاج',           'Sohag'),
  ('شرم الشيخ',       'Sharm El Sheikh'),
  ('شبين الكوم',      'Shebin El Kom'),
  ('طنطا',            'Tanta'),
  ('قنا',             'Qena'),
  ('كفر الشيخ',       'Kafr El Sheikh'),
  ('مرسى مطروح',      'Marsa Matruh');

-- The buyer's picker and the inspector's picker read the same table, so an
-- exact match is guaranteed. This seed is the product's city list; growing it
-- is a one-line insert. The app always writes a canonical value, and the RLS
-- comparison stays plain `lower(btrim(...))` equality.

alter table public.cities enable row level security;

-- Drop Supabase's permissive default grants before stating our own.
revoke all on table public.cities from anon, authenticated;

grant select on table public.cities to anon, authenticated;

create policy cities_select_public
  on public.cities
  for select
  to anon, authenticated
  using (true);