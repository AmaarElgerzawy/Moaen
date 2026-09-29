-- Moaen (معاين) — 0006_cities_saudi.sql
-- Replaces the Egyptian city seed from 0005 with the Saudi list (P10 follow-up).
--
-- 0005 introduced `cities` to stop both sides of the job board typing a city, and
-- seeded it with Egyptian cities because that was the market the product was
-- specified for. The product is Saudi (SAR pricing, الدمام as the reference
-- city), so the seed is swapped here rather than edited in 0005: a migration that
-- has already been applied must not be rewritten, or a fresh database and the
-- live one would disagree.
--
-- Only the list changes. The table, the RLS policy, the `anon` SELECT grant and
-- the free-text `city` / `location_city` columns are all untouched, so the
-- matching guarantee from D17 is unaffected: both sides still select a canonical
-- `name_ar` from this one list.
--
-- Existing rows are not migrated. `city` and `location_city` are free text with
-- no foreign key, so a stale Egyptian city is a real but harmless row that the
-- board simply will not match to a Saudi inspector. Repairing the rows that
-- matter is `tool/set_profile_city.dart`, which exists for exactly this.

delete from public.cities;

insert into public.cities (name_ar, name_en) values
  ('المدينة المنورة',    'Madinah'),
  ('مكة المكرمة',       'Makkah'),
  ('الرياض',            'Riyadh'),
  ('الدمام',            'Dammam'),
  ('الخبر',             'Khobar'),
  ('الظهران',           'Dhahran'),
  ('الجبيل',            'Jubail'),
  ('الأحساء',           'Al Ahsa'),
  ('القطيف',            'Qatif'),
  ('جدة',               'Jeddah'),
  ('بريدة',             'Buraidah'),
  ('تبوك',              'Tabuk'),
  ('الطائف',            'Taif'),
  ('أبها',              'Abha'),
  ('خميس مشيط',        'Khamis Mushait'),
  ('حائل',              'Hail'),
  ('نجران',             'Najran'),
  ('جازان',             'Jazan'),
  ('ينبع',              'Yanbu'),
  ('عرعر',              'Arar'),
  ('سكاكا',             'Sakaka'),
  ('باحة',              'Baha'),
  ('العلا',             'AlUla'),
  ('القنفذة',           'Qunfudhah'),
  ('الأحمدي',           'Ahmadi'),
  ('رابغ',              'Rabigh'),
  ('القلعة',            'Al Qalt'),
  ('وادي الدواسر',      'Wadi ad-Dawasir'),
  ('مستورة',            'Mustatam');
