-- Moaen (معاين) — 0008_seed_centres.sql
-- Seeds the approved inspection centres the design's booking dropdown offers.
--
-- These are rows rather than a list in Dart because the centre's fee is part of
-- the invoice the buyer is shown: a hard-coded dropdown of names cannot produce
-- the 300 that has to appear next to the approved-centre line. The name and the
-- number a buyer approves have to come from the same row, or they can drift.
--
-- `on conflict do nothing` rather than a plain insert, so re-running this against
-- a database that already has the rows — a fresh environment built from a
-- snapshot, or this file applied twice by hand — is a no-op instead of a
-- unique-constraint failure. The pair (name, city) is the natural key the table
-- declares, which is what the conflict target names.
--
-- The fees are placeholders, in the same way `CostEstimate`'s are. They are set
-- in one place here rather than spread across the application so that replacing
-- them with a real price list is a single edit.

insert into public.inspection_centres (name, city, fee) values
  ('مركز كارتك المعتمد',    'الدمام',           300.00),
  ('مركز الفحص الشامل',      'الدمام',           275.00),
  ('مركز برواية للفحص',     'الدمام',           250.00),
  ('مركز الفحص الرقمي',     'الخبر',            260.00),
  ('مركز التجهيز المتقدم',   'الظهران',          290.00),
  ('مركز معروف السيارات',   'الرياض',           320.00),
  ('مركز الراجحي للفحص',    'الرياض',           305.00),
  ('مركز الفحص الموثوق',    'الرياض',           310.00),
  ('مركز السلام للفحص',     'جدة',              280.00),
  ('مركز اليمين للفحص',     'جدة',              295.00),
  ('مركز التقني للفحص',     'مكة المكرمة',      270.00),
  ('مركز المدينة للفحص',    'المدينة المنورة',  265.00)
on conflict (name, city) do nothing;
