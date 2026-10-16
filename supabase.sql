-- Fredags-AW: tabell + säkerhet för anmälningar.
-- Kör hela filen i Supabase: SQL Editor -> New query -> klistra in -> Run.

create table if not exists public.rsvp (
  id         uuid        primary key default gen_random_uuid(),
  name       text        not null check (char_length(btrim(name)) between 1 and 40),
  status     text        not null check (status in ('yes', 'maybe', 'no')),
  token      text        not null check (char_length(token) between 20 and 100),
  created_at timestamptz not null default now()
);

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

alter table public.rsvp enable row level security;

drop policy if exists "alla kan läsa"          on public.rsvp;
drop policy if exists "alla kan anmäla sig"    on public.rsvp;
drop policy if exists "ändra med rätt token"   on public.rsvp;
drop policy if exists "ta bort med rätt token" on public.rsvp;

create policy "alla kan läsa" on public.rsvp
  for select to anon using (true);

create policy "alla kan anmäla sig" on public.rsvp
  for insert to anon with check (true);

create policy "ändra med rätt token" on public.rsvp
  for update to anon
  using (token = public.rsvp_request_token())
  with check (token = public.rsvp_request_token());

create policy "ta bort med rätt token" on public.rsvp
  for delete to anon
  using (token = public.rsvp_request_token());

-- Kolumnrättigheter: token går att skriva men ALDRIG läsa tillbaka,
-- annars kunde vem som helst hämta andras token och ändra deras anmälan.
revoke all on public.rsvp from anon, authenticated;
grant select (id, name, status, created_at) on public.rsvp to anon;
grant insert (name, status, token)          on public.rsvp to anon;
grant update (name, status)                 on public.rsvp to anon;
grant delete                                on public.rsvp to anon;
