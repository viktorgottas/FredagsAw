-- Startpriser för en stor stark (40 cl), från vadkostarolen.se:s guider (oktober 2026).
-- Sajten anger flera priser som ungefärliga ("~"). Priser som redan finns (t.ex. inlagda
-- av gänget) skrivs INTE över. Kör efter supabase.sql: SQL Editor -> New query -> Run.

insert into public.aw_place_price (place_key, place, price, reported_by, updated_at) values
  ('kvarnen',          'Kvarnen',          62, 'vadkostarolen.se (ca)', '2026-10-22'),
  ('pub anchor',       'Pub Anchor',       62, 'vadkostarolen.se (ca)', '2026-10-22'),
  ('pelikan',          'Pelikan',          65, 'vadkostarolen.se (ca)', '2026-10-22'),
  ('akkurat',          'Akkurat',          68, 'vadkostarolen.se (ca)', '2026-10-22'),
  ('wirströms pub',    'Wirströms Pub',    75, 'vadkostarolen.se (ca)', '2026-10-22'),
  ('the liffey',       'The Liffey',       78, 'vadkostarolen.se (ca)', '2026-10-22'),
  ('bar klow',         'Bar Klow',         58, 'vadkostarolen.se',      '2026-10-22'),
  ('soldaten švejk',   'Soldaten Švejk',   58, 'vadkostarolen.se (ca)', '2026-10-22'),
  ('bara vi',          'Bara Vi',          62, 'vadkostarolen.se (ca)', '2026-10-22'),
  ('snotty sounds bar','Snotty Sounds Bar',68, 'vadkostarolen.se (ca)', '2026-10-22'),
  ('häktet',           'Häktet',           70, 'vadkostarolen.se (ca)', '2026-10-22'),
  ('marie laveau',     'Marie Laveau',     72, 'vadkostarolen.se (ca)', '2026-10-22'),
  ('the auld dub',     'The Auld Dub',     80, 'vadkostarolen.se (ca)', '2026-10-22'),
  ('bishops arms',     'Bishops Arms',     82, 'vadkostarolen.se (ca)', '2026-10-22')
on conflict (place_key) do nothing;
