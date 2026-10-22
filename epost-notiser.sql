-- E-postnotiser för AW-appen. Kör hela filen i Supabase (SQL Editor -> New query -> Run).
-- Filen går att köra flera gånger.
--
-- Vem får vad?
--   * Du (notify_email):  nytt förslag, ändrad tid/plats och nya kommentarer.
--   * Prenumeranter:      bara nytt förslag och ändrad tid/plats.
--     Alla kan prenumerera från sidan; varje mejl har en avregistreringslänk.
--
-- Mejltjänst – välj en:
--   * Brevo (https://brevo.com, gratis 300 mejl/dag): kan mejla vem som helst utan egen domän.
--     Verifiera din avsändaradress under Senders, skapa en API-nyckel (SMTP & API -> API Keys).
--   * Resend (https://resend.com): utan egen domän går mejl BARA till din egen adress,
--     så prenumeranter fungerar först när du verifierat en domän där.
--
-- Inställningar (kör separat, byt värdena; rader du inte behöver kan du hoppa över):
--
--   insert into public.aw_settings (key, value) values
--     ('mail_provider', 'brevo'),                 -- 'brevo' eller 'resend'
--     ('brevo_api_key', 'xkeysib-...'),           -- om Brevo
--     ('resend_api_key', 're_...'),               -- om Resend
--     ('sender_email',  'din@mejl.se'),           -- verifierad avsändare (krävs för Brevo)
--     ('notify_email',  'din@mejl.se'),           -- du får allt
--     ('site_url',      'https://ditt-namn.github.io/repo/')
--   on conflict (key) do update set value = excluded.value;
--
-- Stänga av alla mejl: delete from public.aw_settings where key in ('brevo_api_key', 'resend_api_key');

create extension if not exists pg_net with schema extensions;

-- ---------- Inställningar (går inte att läsa via API:t) ----------
create table if not exists public.aw_settings (
  key   text primary key,
  value text not null
);
alter table public.aw_settings enable row level security;
revoke all on public.aw_settings from anon, authenticated;

-- ---------- Prenumeranter (går inte att läsa via API:t) ----------
create table if not exists public.aw_subscriber (
  id          uuid        primary key default gen_random_uuid(),
  email       text        not null,
  unsub_token uuid        not null default gen_random_uuid(),
  created_at  timestamptz not null default now()
);
create unique index if not exists aw_subscriber_email on public.aw_subscriber (lower(email));
create unique index if not exists aw_subscriber_token on public.aw_subscriber (unsub_token);
alter table public.aw_subscriber enable row level security;
revoke all on public.aw_subscriber from anon, authenticated;

-- ---------- Hjälpfunktioner ----------
create or replace function public.aw_setting(k text)
returns text
language sql
stable
security definer
set search_path = public
as $$ select nullif(btrim(value), '') from public.aw_settings where key = k $$;

create or replace function public.aw_html(t text)
returns text
language sql
immutable
as $$
  select replace(replace(replace(replace(coalesce(t, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;')
$$;

create or replace function public.aw_format_time(ts timestamptz)
returns text
language sql
stable
as $$
  select (array['söndag','måndag','tisdag','onsdag','torsdag','fredag','lördag'])
           [extract(dow from ts at time zone 'Europe/Stockholm')::int + 1]
      || ' ' || extract(day from ts at time zone 'Europe/Stockholm')::int
      || ' ' || (array['januari','februari','mars','april','maj','juni','juli',
                       'augusti','september','oktober','november','december'])
           [extract(month from ts at time zone 'Europe/Stockholm')::int]
      || ' kl. ' || to_char(ts at time zone 'Europe/Stockholm', 'HH24.MI')
$$;

-- Skickar ett mejl via vald tjänst. Fel loggas men stoppar aldrig något annat.
create or replace function public.aw_send_mail(p_to text, p_subject text, p_html text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  provider text := coalesce(aw_setting('mail_provider'), 'resend');
  sender   text := aw_setting('sender_email');
  doc      text := '<div style="font-family:Arial,sans-serif;font-size:16px;line-height:1.5;color:#15231c">'
                   || p_html || '</div>';
begin
  if p_to is null then return; end if;
  if provider = 'brevo' then
    if aw_setting('brevo_api_key') is null or sender is null then return; end if;
    perform net.http_post(
      url     := 'https://api.brevo.com/v3/smtp/email',
      headers := jsonb_build_object('api-key', aw_setting('brevo_api_key'),
                                    'Content-Type', 'application/json', 'Accept', 'application/json'),
      body    := jsonb_build_object(
                   'sender', jsonb_build_object('name', 'AW-appen', 'email', sender),
                   'to', jsonb_build_array(jsonb_build_object('email', p_to)),
                   'subject', left(p_subject, 200),
                   'htmlContent', doc)
    );
  else
    if aw_setting('resend_api_key') is null then return; end if;
    perform net.http_post(
      url     := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization', 'Bearer ' || aw_setting('resend_api_key'),
                                    'Content-Type', 'application/json'),
      body    := jsonb_build_object(
                   'from', 'AW-appen <' || coalesce(sender, 'onboarding@resend.dev') || '>',
                   'to', jsonb_build_array(p_to),
                   'subject', left(p_subject, 200),
                   'html', doc)
    );
  end if;
exception when others then
  raise warning 'AW-mejl kunde inte skickas: %', sqlerrm;
end
$$;

-- Mejl till alla prenumeranter (en i taget, med egen avregistreringslänk)
create or replace function public.aw_mail_subscribers(p_subject text, p_html text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  site  text := aw_setting('site_url');
  owner text := lower(coalesce(aw_setting('notify_email'), ''));
  s     record;
begin
  if site is null then return; end if;  -- utan site_url kan vi inte länka till avregistrering
  for s in select email, unsub_token from aw_subscriber where lower(email) <> owner loop
    perform aw_send_mail(s.email, p_subject,
      p_html
      || '<p><a href="' || aw_html(site) || '">Öppna AW-appen</a></p>'
      || '<p style="font-size:13px;color:#55665d">Du får det här mejlet för att du prenumererar på nya AW:er. '
      || '<a href="' || aw_html(site) || '?avregistrera=' || s.unsub_token || '">Avregistrera</a></p>');
  end loop;
end
$$;

-- ---------- Triggers ----------
create or replace function public.aw_notify_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  site    text := aw_setting('site_url');
  owner   text := aw_setting('notify_email');
  link    text := case when site is not null
                       then '<p><a href="' || aw_html(site) || '">Öppna AW-appen</a></p>' else '' end;
  subject text;
  html    text;
  p       aw_proposal;
begin
  if tg_table_name = 'aw_comment' then
    select * into p from aw_proposal where id = new.proposal_id;
    subject := 'Ny kommentar från ' || new.name || ' på ' || coalesce(p.place, 'ett förslag');
    html := '<h2>' || aw_html(new.name) || ' kommenterade</h2>'
         || '<p><b>' || aw_html(p.place) || '</b>, ' || aw_html(aw_format_time(p.starts_at)) || '</p>'
         || '<blockquote style="border-left:3px solid #a8731a;margin:0;padding:4px 12px">'
         || replace(aw_html(new.body), E'\n', '<br>') || '</blockquote>';
    perform aw_send_mail(owner, subject, html || link);   -- kommentarer: bara till dig
    return new;
  end if;

  if tg_op = 'INSERT' and new.reveal_at is not null then
    subject := '🤫 Ny AW på hemligt ställe, ' || aw_format_time(new.starts_at);
    html := '<h2>' || aw_html(new.created_by) || ' bjuder in till en hemlig AW 🤫</h2>'
         || '<p><b>' || aw_html(aw_format_time(new.starts_at)) || '</b><br>'
         || 'Platsen avslöjas ' || aw_html(aw_format_time(new.reveal_at)) || '.</p>'
         || case when new.note is not null then '<p>' || aw_html(new.note) || '</p>' else '' end
         || '<p>Säg till i appen om du kommer!</p>';
  elsif tg_op = 'UPDATE' and old.reveal_at is not null and new.reveal_at is null then
    subject := '🤫 Avslöjat: AW på ' || new.place || ', ' || aw_format_time(new.starts_at);
    html := '<h2>Platsen är avslöjad! 🎉</h2>'
         || '<p><b>' || aw_html(new.place) || '</b><br>' || aw_html(aw_format_time(new.starts_at)) || '</p>'
         || '<p>Vi ses där!</p>';
  elsif tg_op = 'INSERT' then
    subject := 'Ny AW: ' || new.place || ', ' || aw_format_time(new.starts_at);
    html := '<h2>' || aw_html(new.created_by) || ' föreslår en AW</h2>'
         || '<p><b>' || aw_html(new.place) || '</b><br>' || aw_html(aw_format_time(new.starts_at)) || '</p>'
         || case when new.note is not null then '<p>' || aw_html(new.note) || '</p>' else '' end
         || '<p>Säg till i appen om du kommer!</p>';
  else
    subject := 'Ändrad AW: ' || new.place || ', ' || aw_format_time(new.starts_at);
    html := '<h2>AW:n är ändrad</h2>'
         || '<p><b>Nu:</b> ' || aw_html(new.place) || ', ' || aw_html(aw_format_time(new.starts_at)) || '<br>'
         || '<span style="color:#55665d"><b>Förut:</b> <s>' || aw_html(old.place) || ', '
         || aw_html(aw_format_time(old.starts_at)) || '</s></span></p>'
         || case when new.note is not null then '<p>' || aw_html(new.note) || '</p>' else '' end
         || '<p>Kolla i appen att du fortfarande kan.</p>';
  end if;

  perform aw_send_mail(owner, subject, html || link);
  perform aw_mail_subscribers(subject, html);
  return new;
exception when others then
  raise warning 'AW-notis misslyckades: %', sqlerrm;
  return new;
end
$$;

drop trigger if exists aw_proposal_notify on public.aw_proposal;
create trigger aw_proposal_notify after insert on public.aw_proposal
  for each row execute function public.aw_notify_email();

drop trigger if exists aw_proposal_changed_notify on public.aw_proposal;
create trigger aw_proposal_changed_notify after update on public.aw_proposal
  for each row
  when (old.place is distinct from new.place or old.starts_at is distinct from new.starts_at)
  execute function public.aw_notify_email();

drop trigger if exists aw_comment_notify on public.aw_comment;
create trigger aw_comment_notify after insert on public.aw_comment
  for each row execute function public.aw_notify_email();

-- ---------- Prenumerera / avregistrera (anropas från sidan) ----------
create or replace function public.aw_subscribe(p_email text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  e   text := lower(btrim(coalesce(p_email, '')));
  tok uuid;
begin
  if length(e) > 254 or e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Ogiltig e-postadress' using errcode = '22023';
  end if;
  insert into aw_subscriber (email) values (e)
    on conflict (lower(email)) do nothing
    returning unsub_token into tok;
  if tok is null then
    return 'redan';
  end if;
  if aw_setting('site_url') is not null then
    perform aw_send_mail(e, 'Du prenumererar på AW-appen',
      '<h2>Välkommen!</h2><p>Du får ett mejl när en ny AW föreslås eller när tid eller plats ändras.</p>'
      || '<p><a href="' || aw_html(aw_setting('site_url')) || '">Öppna AW-appen</a></p>'
      || '<p>Tips: lägg in AW-kalendern i din iPhone-, Google- eller Outlook-kalender, så dyker '
      || 'alla AW:er upp där automatiskt: <a href="' || aw_html(aw_setting('site_url')) || '#kalender">'
      || 'Lägg till kalendern</a></p>'
      || '<p style="font-size:13px;color:#55665d">Var det inte du som anmälde dig? '
      || '<a href="' || aw_html(aw_setting('site_url')) || '?avregistrera=' || tok || '">Avregistrera</a></p>');
  end if;
  return 'ny';
end
$$;

create or replace function public.aw_unsubscribe(p_token uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from aw_subscriber where unsub_token = p_token;
  return found;
end
$$;

-- Bara API-funktionerna får anropas utifrån
revoke all on function public.aw_setting(text)                    from public, anon, authenticated;
revoke all on function public.aw_send_mail(text, text, text)      from public, anon, authenticated;
revoke all on function public.aw_mail_subscribers(text, text)     from public, anon, authenticated;
revoke all on function public.aw_notify_email()                   from public, anon, authenticated;
revoke all on function public.aw_subscribe(text)                  from public, anon, authenticated;
revoke all on function public.aw_unsubscribe(uuid)                from public, anon, authenticated;
grant execute on function public.aw_subscribe(text)   to anon;
grant execute on function public.aw_unsubscribe(uuid) to anon;
