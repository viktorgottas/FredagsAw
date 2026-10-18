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

create policy "alla kan läsa förslag" on public.aw_proposal
  for select to anon using (true);
create policy "alla kan föreslå" on public.aw_proposal
  for insert to anon with check (true);
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
grant select (id, place, starts_at, note, created_by, created_at) on public.aw_proposal to anon;
grant insert (place, starts_at, note, created_by, token)         on public.aw_proposal to anon;
grant delete                                                     on public.aw_proposal to anon;

revoke all on public.rsvp from anon, authenticated;
grant select (id, proposal_id, name, status, created_at) on public.rsvp to anon;
grant insert (proposal_id, name, status, token)          on public.rsvp to anon;
grant update (name, status)                              on public.rsvp to anon;
grant delete                                             on public.rsvp to anon;

-- Gamla svar från första versionen (utan förslag) visas inte längre.
-- Vill du städa bort dem: delete from public.rsvp where proposal_id is null;
