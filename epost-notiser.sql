-- E-postnotiser: ett mejl när någon lägger ett förslag eller skriver en kommentar.
-- Mejlen skickas via Resend (https://resend.com, gratis upp till 100 mejl/dag).
--
-- 1. Kör hela den här filen i Supabase: SQL Editor -> New query -> klistra in -> Run.
-- 2. Lägg in dina inställningar (kör separat, byt värdena):
--
--      insert into public.aw_settings (key, value) values
--        ('resend_api_key', 're_DIN_NYCKEL'),
--        ('notify_email',   'din@mejl.se'),
--        ('site_url',       'https://ditt-namn.github.io/repo/')
--      on conflict (key) do update set value = excluded.value;
--
--    Utan egen domän i Resend går det bara att skicka till mejladressen du skapade kontot med.
-- Stänga av: delete from public.aw_settings where key = 'resend_api_key';

create extension if not exists pg_net with schema extensions;

-- Inställningar (går inte att läsa via API:t)
create table if not exists public.aw_settings (
  key   text primary key,
  value text not null
);
alter table public.aw_settings enable row level security;
revoke all on public.aw_settings from anon, authenticated;

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

create or replace function public.aw_notify_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  api_key  text := (select value from aw_settings where key = 'resend_api_key');
  mail_to  text := (select value from aw_settings where key = 'notify_email');
  site     text := coalesce((select value from aw_settings where key = 'site_url'), '');
  subject  text;
  html     text;
  p        aw_proposal;
begin
  if api_key is null or mail_to is null then
    return new;  -- notiser inte inställda
  end if;

  if tg_table_name = 'aw_proposal' then
    subject := 'Nytt AW-förslag: ' || new.place || ', ' || aw_format_time(new.starts_at);
    html := '<h2>' || aw_html(new.created_by) || ' föreslår en AW</h2>'
         || '<p><b>' || aw_html(new.place) || '</b><br>' || aw_html(aw_format_time(new.starts_at)) || '</p>'
         || case when new.note is not null then '<p>' || aw_html(new.note) || '</p>' else '' end;
  else
    select * into p from aw_proposal where id = new.proposal_id;
    subject := 'Ny kommentar från ' || new.name || ' på ' || coalesce(p.place, 'ett förslag');
    html := '<h2>' || aw_html(new.name) || ' kommenterade</h2>'
         || '<p><b>' || aw_html(p.place) || '</b>, ' || aw_html(aw_format_time(p.starts_at)) || '</p>'
         || '<blockquote style="border-left:3px solid #a8731a;margin:0;padding:4px 12px">'
         || replace(aw_html(new.body), E'\n', '<br>') || '</blockquote>';
  end if;

  if site <> '' then
    html := html || '<p><a href="' || aw_html(site) || '">Öppna AW-appen</a></p>';
  end if;

  begin
    perform net.http_post(
      url     := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
      body    := jsonb_build_object(
                   'from', 'AW-appen <onboarding@resend.dev>',
                   'to', jsonb_build_array(mail_to),
                   'subject', left(subject, 200),
                   'html', html)
    );
  exception when others then
    -- Ett mejlfel får aldrig stoppa att förslaget/kommentaren sparas
    raise warning 'AW-notis kunde inte skickas: %', sqlerrm;
  end;
  return new;
end
$$;

revoke all on function public.aw_notify_email() from public, anon, authenticated;

drop trigger if exists aw_proposal_notify on public.aw_proposal;
create trigger aw_proposal_notify after insert on public.aw_proposal
  for each row execute function public.aw_notify_email();

drop trigger if exists aw_comment_notify on public.aw_comment;
create trigger aw_comment_notify after insert on public.aw_comment
  for each row execute function public.aw_notify_email();
