-- AW-sidan: förslag (var + när) och svar per förslag.
-- Kör hela filen i Supabase: SQL Editor -> New query -> klistra in -> Run.
-- Filen går att köra flera gånger; den uppgraderar en äldre installation.

-- ---------- Förslag ----------
create table if not exists public.aw_proposal (
  id         uuid        primary key default gen_random_uuid(),
  place      text        not null check (char_length(btrim(place)) between 1 and 60),
  starts_at  timestamptz not null,
  note       text        check (note is null or char_length(note) <= 140),
  created_by text        not null check (char_length(btrim(created_by)) between 1 and 40),
  token      text        not null check (char_length(token) between 20 and 100),
  created_at timestamptz not null default now()
);

-- Nyare kolumner: vem bjuder på första rundan, och hemlig plats som avslöjas vid reveal_at.
alter table public.aw_proposal add column if not exists buyer_name   text;
alter table public.aw_proposal add column if not exists secret_place text;
alter table public.aw_proposal add column if not exists reveal_at    timestamptz;
alter table public.aw_proposal add column if not exists buyer_pool   text[];  -- vilka som var med när det slumpades
alter table public.aw_proposal drop constraint if exists aw_proposal_secret_check;
alter table public.aw_proposal add constraint aw_proposal_secret_check check (
  (secret_place is null) = (reveal_at is null)
  and (secret_place is null or char_length(btrim(secret_place)) between 1 and 60)
);

-- ---------- Svar ----------
create table if not exists public.rsvp (
  id         uuid        primary key default gen_random_uuid(),
  name       text        not null check (char_length(btrim(name)) between 1 and 40),
  status     text        not null check (status in ('yes', 'maybe', 'no')),
  token      text        not null check (char_length(token) between 20 and 100),
  created_at timestamptz not null default now()
);

alter table public.rsvp
  add column if not exists proposal_id uuid references public.aw_proposal (id) on delete cascade;

-- Ett svar per webbläsare och förslag.
create unique index if not exists rsvp_one_per_proposal on public.rsvp (proposal_id, token);

-- Läser token från HTTP-headern "x-rsvp-token" som sidan skickar med.
create or replace function public.rsvp_request_token()
returns text
language sql
stable
as $$
  select nullif(
    coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'x-rsvp-token',
    ''
  )
$$;

alter table public.aw_proposal enable row level security;
alter table public.rsvp        enable row level security;

-- Policyer för förslag
drop policy if exists "alla kan läsa förslag"          on public.aw_proposal;
drop policy if exists "alla kan föreslå"               on public.aw_proposal;
drop policy if exists "ta bort förslag med rätt token" on public.aw_proposal;
drop policy if exists "ändra förslag med rätt token"   on public.aw_proposal;

create policy "alla kan läsa förslag" on public.aw_proposal
  for select to anon using (true);
create policy "alla kan föreslå" on public.aw_proposal
  for insert to anon with check (true);
create policy "ändra förslag med rätt token" on public.aw_proposal
  for update to anon
  using (token = public.rsvp_request_token())
  with check (token = public.rsvp_request_token());
create policy "ta bort förslag med rätt token" on public.aw_proposal
  for delete to anon using (token = public.rsvp_request_token());

-- Policyer för svar
drop policy if exists "alla kan läsa"          on public.rsvp;
drop policy if exists "alla kan anmäla sig"    on public.rsvp;
drop policy if exists "ändra med rätt token"   on public.rsvp;
drop policy if exists "ta bort med rätt token" on public.rsvp;

create policy "alla kan läsa" on public.rsvp
  for select to anon using (true);
create policy "alla kan anmäla sig" on public.rsvp
  for insert to anon with check (proposal_id is not null);
create policy "ändra med rätt token" on public.rsvp
  for update to anon
  using (token = public.rsvp_request_token())
  with check (token = public.rsvp_request_token());
create policy "ta bort med rätt token" on public.rsvp
  for delete to anon
  using (token = public.rsvp_request_token());

-- Kolumnrättigheter: token går att skriva men ALDRIG läsa tillbaka,
-- annars kunde vem som helst hämta andras token och ändra deras svar.
revoke all on public.aw_proposal from anon, authenticated;
-- secret_place går att skriva men inte läsa: den hemliga platsen syns först när den avslöjas.
grant select (id, place, starts_at, note, created_by, created_at, buyer_name, reveal_at, buyer_pool) on public.aw_proposal to anon;
grant insert (place, starts_at, note, created_by, token, secret_place, reveal_at)        on public.aw_proposal to anon;
grant update (place, starts_at, note)                            on public.aw_proposal to anon;
grant delete                                                     on public.aw_proposal to anon;

revoke all on public.rsvp from anon, authenticated;
grant select (id, proposal_id, name, status, created_at) on public.rsvp to anon;
grant insert (proposal_id, name, status, token)          on public.rsvp to anon;
grant update (name, status)                              on public.rsvp to anon;
grant delete                                             on public.rsvp to anon;

-- ---------- Kommentarer ----------
create table if not exists public.aw_comment (
  id          uuid        primary key default gen_random_uuid(),
  proposal_id uuid        not null references public.aw_proposal (id) on delete cascade,
  name        text        not null check (char_length(btrim(name)) between 1 and 40),
  body        text        not null check (char_length(btrim(body)) between 1 and 280),
  token       text        not null check (char_length(token) between 20 and 100),
  created_at  timestamptz not null default now()
);
create index if not exists aw_comment_proposal on public.aw_comment (proposal_id, created_at);

alter table public.aw_comment enable row level security;

drop policy if exists "alla kan läsa kommentarer"          on public.aw_comment;
drop policy if exists "alla kan kommentera"                on public.aw_comment;
drop policy if exists "ta bort kommentar med rätt token"   on public.aw_comment;

create policy "alla kan läsa kommentarer" on public.aw_comment
  for select to anon using (true);
create policy "alla kan kommentera" on public.aw_comment
  for insert to anon with check (true);
create policy "ta bort kommentar med rätt token" on public.aw_comment
  for delete to anon using (token = public.rsvp_request_token());

revoke all on public.aw_comment from anon, authenticated;
grant select (id, proposal_id, name, body, created_at) on public.aw_comment to anon;
grant insert (proposal_id, name, body, token)          on public.aw_comment to anon;
grant delete                                           on public.aw_comment to anon;

-- ---------- Städning ----------
-- Tar bort förslag vars dag (svensk tid) har passerat och som ingen svarade "kommer" på.
-- AW:er som blev av sparas (för topplistan och bilderna) men visas inte bland förslagen.
-- Sidan anropar den när någon öppnar den. Den kan bara radera passerade förslag.
create or replace function public.cleanup_past_proposals()
returns integer
language sql
security definer
set search_path = public
as $$
  with removed as (
    delete from public.aw_proposal
    where (starts_at at time zone 'Europe/Stockholm')::date
        < (now() at time zone 'Europe/Stockholm')::date
      and not exists (select 1 from public.rsvp r where r.proposal_id = aw_proposal.id and r.status = 'yes')
    returning 1
  )
  select count(*)::int from removed
$$;
revoke all on function public.cleanup_past_proposals() from public, anon, authenticated;
grant execute on function public.cleanup_past_proposals() to anon;

-- ---------- Admin ----------
-- Den som har admin-koden kan ta bort vilket förslag som helst.
-- Koden lagras som SHA-256-hash och tabellen går inte att läsa via API:t.
-- Lägg in en kod (kör separat i SQL Editor, byt HEMLIG-KOD mot din egen):
--   insert into public.aw_admin (code_hash)
--   values (encode(sha256(convert_to('HEMLIG-KOD', 'UTF8')), 'hex'));
create table if not exists public.aw_admin (
  code_hash  text        primary key,
  created_at timestamptz not null default now()
);
alter table public.aw_admin enable row level security;
revoke all on public.aw_admin from anon, authenticated;

create or replace function public.admin_check(p_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.aw_admin
    where code_hash = encode(sha256(convert_to(coalesce(p_code, ''), 'UTF8')), 'hex')
  )
$$;

create or replace function public.admin_delete_proposal(p_id uuid, p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.admin_check(p_code) then
    raise exception 'Fel admin-kod' using errcode = '42501';
  end if;
  delete from public.aw_proposal where id = p_id;
  return found;
end
$$;

create or replace function public.admin_update_proposal(
  p_id uuid, p_place text, p_starts_at timestamptz, p_note text, p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.admin_check(p_code) then
    raise exception 'Fel admin-kod' using errcode = '42501';
  end if;
  update public.aw_proposal
     set place = p_place, starts_at = p_starts_at, note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_id;
  return found;
end
$$;

create or replace function public.admin_delete_comment(p_id uuid, p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.admin_check(p_code) then
    raise exception 'Fel admin-kod' using errcode = '42501';
  end if;
  delete from public.aw_comment where id = p_id;
  return found;
end
$$;

revoke all on function public.admin_check(text)                 from public, anon, authenticated;
revoke all on function public.admin_delete_comment(uuid, text)  from public, anon, authenticated;
revoke all on function public.admin_update_proposal(uuid, text, timestamptz, text, text) from public, anon, authenticated;
grant execute on function public.admin_update_proposal(uuid, text, timestamptz, text, text) to anon;
grant execute on function public.admin_delete_comment(uuid, text)  to anon;
revoke all on function public.admin_delete_proposal(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_check(text)                 to anon;
grant execute on function public.admin_delete_proposal(uuid, text) to anon;

-- Gamla svar från första versionen (utan förslag) visas inte längre.
-- Vill du städa bort dem: delete from public.rsvp where proposal_id is null;

-- ---------- Hemlig plats ----------
-- Avslöjar hemliga platser vars tid har kommit. Körs varje minut av pg_cron (om det finns)
-- och dessutom när någon öppnar sidan.
create or replace function public.aw_reveal_due()
returns integer
language sql
security definer
set search_path = public
as $$
  with revealed as (
    update public.aw_proposal
       set place = secret_place, secret_place = null, reveal_at = null
     where reveal_at is not null and reveal_at <= now()
    returning 1
  )
  select count(*)::int from revealed
$$;
revoke all on function public.aw_reveal_due() from public, anon, authenticated;
grant execute on function public.aw_reveal_due() to anon;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      create extension if not exists pg_cron;
    exception when others then
      raise notice 'pg_cron kunde inte aktiveras (%). Slå på det under Database → Extensions och kör filen igen.', sqlerrm;
    end;
  end if;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('aw-reveal', '* * * * *', 'select public.aw_reveal_due()');
  end if;
exception when others then
  raise notice 'Kunde inte schemalägga avslöjandet (%). Platser avslöjas ändå när någon öppnar sidan.', sqlerrm;
end
$$;

-- ---------- Vem bjuder på första rundan? ----------
-- Slumpar bland dem som svarat "kommer". Redan slumpat = samma svar (admin kan slumpa om).
create or replace function public.aw_draw_buyer(p_id uuid, p_code text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_buyer text;
  pool text[];
  yes_names text[];
  is_admin boolean := admin_check(p_code);
  newcomers boolean;
  pick text;
begin
  select buyer_name, buyer_pool into current_buyer, pool from aw_proposal where id = p_id for update;
  if not found then
    raise exception 'Förslaget finns inte' using errcode = '23503';
  end if;
  select coalesce(array_agg(name), '{}') into yes_names from rsvp where proposal_id = p_id and status = 'yes';
  -- Nya som kommer sedan förra slumpningen? Då får vem som helst slumpa om.
  newcomers := current_buyer is not null and pool is not null
               and exists (select 1 from unnest(yes_names) n where not (n = any(pool)));
  if current_buyer is not null and not is_admin and not newcomers then
    return current_buyer;
  end if;
  select n into pick from unnest(yes_names) n
   where newcomers or current_buyer is null or n <> current_buyer or cardinality(yes_names) = 1
   order by random() limit 1;
  if pick is null then
    raise exception 'Ingen har svarat kommer än' using errcode = '22023';
  end if;
  update aw_proposal set buyer_name = pick, buyer_pool = yes_names where id = p_id;
  return pick;
end
$$;
-- Admin: ta bort någons svar (nollställer "vem bjuder" om det var den personen)
create or replace function public.admin_delete_rsvp(p_id uuid, p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare r rsvp;
begin
  if not admin_check(p_code) then
    raise exception 'Fel admin-kod' using errcode = '42501';
  end if;
  delete from rsvp where id = p_id returning * into r;
  if r.id is null then return false; end if;
  update aw_proposal set buyer_name = null, buyer_pool = null
   where id = r.proposal_id and buyer_name = r.name
     and not exists (select 1 from rsvp x where x.proposal_id = r.proposal_id and x.status = 'yes' and x.name = r.name);
  return true;
end
$$;

-- Admin: nollställ "vem bjuder på första rundan"
create or replace function public.admin_clear_buyer(p_id uuid, p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not admin_check(p_code) then
    raise exception 'Fel admin-kod' using errcode = '42501';
  end if;
  update aw_proposal set buyer_name = null, buyer_pool = null where id = p_id;
  return found;
end
$$;
revoke all on function public.admin_delete_rsvp(uuid, text) from public, anon, authenticated;
revoke all on function public.admin_clear_buyer(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_delete_rsvp(uuid, text) to anon;
grant execute on function public.admin_clear_buyer(uuid, text) to anon;

revoke all on function public.aw_draw_buyer(uuid, text) from public, anon, authenticated;
grant execute on function public.aw_draw_buyer(uuid, text) to anon;

-- Slumpningar gjorda innan buyer_pool fanns: räkna nuvarande deltagare som med i dragningen.
update public.aw_proposal p
   set buyer_pool = (select coalesce(array_agg(name), '{}') from public.rsvp r
                      where r.proposal_id = p.id and r.status = 'yes')
 where buyer_name is not null and buyer_pool is null;

-- ---------- Topplista ----------
create or replace function public.aw_stats()
returns table (name text, attended int, proposed int, maybes int)
language sql
stable
security definer
set search_path = public
as $$
  with people as (
    select lower(btrim(r.name)) as k, r.name,
           (r.status = 'yes'   and p.starts_at < now())::int as att,
           (r.status = 'maybe' and p.starts_at < now())::int as may,
           0 as prop
      from rsvp r join aw_proposal p on p.id = r.proposal_id
    union all
    select lower(btrim(created_by)), created_by, 0, 0, 1 from aw_proposal
  )
  select max(name), sum(att)::int, sum(prop)::int, sum(may)::int
    from people group by k
$$;
revoke all on function public.aw_stats() from public, anon, authenticated;
grant execute on function public.aw_stats() to anon;

-- ---------- Bilder ----------
-- Filerna ligger i Storage-bucketen "aw-photos" (publik läsning); tabellen håller ordning
-- på vilka bilder som hör till vilken AW och vem som lade upp dem.
create table if not exists public.aw_photo (
  id          uuid        primary key default gen_random_uuid(),
  proposal_id uuid        not null references public.aw_proposal (id) on delete cascade,
  path        text        not null unique check (path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$'),
  name        text        not null check (char_length(btrim(name)) between 1 and 40),
  token       text        not null check (char_length(token) between 20 and 100),
  created_at  timestamptz not null default now()
);
create index if not exists aw_photo_proposal on public.aw_photo (proposal_id, created_at);
alter table public.aw_photo enable row level security;

drop policy if exists "alla kan se bilder"            on public.aw_photo;
drop policy if exists "alla kan lägga upp bilder"     on public.aw_photo;
drop policy if exists "ta bort bild med rätt token"   on public.aw_photo;
create policy "alla kan se bilder" on public.aw_photo
  for select to anon using (true);
create policy "alla kan lägga upp bilder" on public.aw_photo
  for insert to anon with check (path like proposal_id::text || '/%');
create policy "ta bort bild med rätt token" on public.aw_photo
  for delete to anon using (token = public.rsvp_request_token());

revoke all on public.aw_photo from anon, authenticated;
grant select (id, proposal_id, path, name, created_at) on public.aw_photo to anon;
grant insert (proposal_id, path, name, token)          on public.aw_photo to anon;
grant delete                                           on public.aw_photo to anon;

create or replace function public.admin_delete_photo(p_id uuid, p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.admin_check(p_code) then
    raise exception 'Fel admin-kod' using errcode = '42501';
  end if;
  delete from public.aw_photo where id = p_id;
  return found;
end
$$;
revoke all on function public.admin_delete_photo(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_delete_photo(uuid, text) to anon;

-- Storage-bucket: publik läsning, uppladdning av jpg (max 5 MB) för alla med appen.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('aw-photos', 'aw-photos', true, 5242880, array['image/jpeg'])
on conflict (id) do update
  set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "aw-photos uppladdning" on storage.objects;
create policy "aw-photos uppladdning" on storage.objects
  for insert to anon
  with check (bucket_id = 'aw-photos' and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$');

-- ---------- Pris på en stor stark ----------
-- Ett pris per ställe (nyckel = namnet före första kommatecknet, gemener), så det följer med
-- till alla framtida förslag på samma ställe. Vem som helst kan lägga in/uppdatera via aw_set_price.
create table if not exists public.aw_place_price (
  place_key   text        primary key,
  place       text        not null,
  price       int         not null check (price between 10 and 300),
  reported_by text        not null check (char_length(btrim(reported_by)) between 1 and 40),
  updated_at  timestamptz not null default now()
);
alter table public.aw_place_price enable row level security;
drop policy if exists "alla kan se priser" on public.aw_place_price;
create policy "alla kan se priser" on public.aw_place_price for select to anon using (true);
revoke all on public.aw_place_price from anon, authenticated;
grant select (place_key, place, price, reported_by, updated_at) on public.aw_place_price to anon;

create or replace function public.aw_place_key(p_place text)
returns text
language sql
immutable
as $$ select btrim(lower(split_part(coalesce(p_place, ''), ',', 1))) $$;

create or replace function public.aw_set_price(p_place text, p_price int, p_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare k text := aw_place_key(p_place);
begin
  if k = '' or char_length(k) > 60 then
    raise exception 'Ogiltigt ställe' using errcode = '22023';
  end if;
  if p_price is null or p_price < 10 or p_price > 300 then
    raise exception 'Priset måste vara mellan 10 och 300 kr' using errcode = '22023';
  end if;
  insert into aw_place_price (place_key, place, price, reported_by, updated_at)
  values (k, btrim(split_part(p_place, ',', 1)), p_price, btrim(p_name), now())
  on conflict (place_key) do update
    set price = excluded.price, reported_by = excluded.reported_by, updated_at = now();
end
$$;
revoke all on function public.aw_set_price(text, int, text) from public, anon, authenticated;
grant execute on function public.aw_set_price(text, int, text) to anon;
