// Supabase Edge Function "aw-ics": kalenderfiler för AW-appen.
//
//   .../functions/v1/aw-ics?id=<förslagets id>  -> ett förslag (iPhone visar "Lägg till i Kalender")
//   .../functions/v1/aw-ics                     -> prenumerationskalender med alla kommande förslag
//                                                 (läggs in en gång i iPhone/Google/Outlook och
//                                                 uppdateras automatiskt)
//
// Viktigt: stäng av "Verify JWT" för funktionen, annars kan kalenderappar inte hämta den.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "*" };
const DURATION_MS = 3 * 3600 * 1000;

type Proposal = { id: string; place: string; starts_at: string; note: string | null; created_by: string };
type Rsvp = { proposal_id: string; status: "yes" | "maybe" | "no" };

async function rest<T>(path: string): Promise<T> {
  const headers: Record<string, string> = { apikey: KEY, Accept: "application/json" };
  if (KEY.startsWith("eyJ")) headers.Authorization = "Bearer " + KEY;
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers });
  if (!res.ok) throw new Error(`REST ${res.status}: ${await res.text()}`);
  return await res.json() as T;
}

const icsDate = (ms: number) => new Date(ms).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
const icsEscape = (t: string) =>
  t.replace(/\\/g, "\\\\").replace(/[,;]/g, (m) => "\\" + m).replace(/\r?\n/g, "\\n");

// Raderna i en .ics får vara max 75 byte; längre rader viks med CRLF + mellanslag.
function fold(line: string): string {
  const enc = new TextEncoder();
  const out: string[] = [];
  let cur = "";
  for (const ch of line) {
    if (enc.encode(cur + ch).length > (out.length ? 74 : 75)) { out.push(cur); cur = ""; }
    cur += ch;
  }
  out.push(cur);
  return out.join("\r\n ");
}

function text(body: string, status: number) {
  return new Response(body, { status, headers: { ...CORS, "Content-Type": "text/plain; charset=utf-8" } });
}

async function siteUrl(): Promise<string> {
  try {
    const s = await rest<{ value: string }[]>("aw_settings?key=eq.site_url&select=value");
    return s[0]?.value ?? "";
  } catch {
    return ""; // inställningen är valfri
  }
}

function eventLines(p: Proposal, site: string, counts?: { yes: number; maybe: number }): string[] {
  const start = new Date(p.starts_at).getTime();
  const link = site ? site + "#forslag-" + p.id : "";
  const parts: string[] = [];
  if (p.note) parts.push(p.note);
  if (counts) {
    parts.push(`${counts.yes} kommer` + (counts.maybe ? `, ${counts.maybe} kanske` : "") + ` · föreslaget av ${p.created_by}`);
  }
  if (link) parts.push("Svara här: " + link);
  return [
    "BEGIN:VEVENT",
    "UID:" + p.id + "@aw-appen",
    "DTSTAMP:" + icsDate(Date.now()),
    "DTSTART:" + icsDate(start),
    "DTEND:" + icsDate(start + DURATION_MS),
    "SUMMARY:" + icsEscape("AW: " + p.place),
    "LOCATION:" + icsEscape(p.place),
    ...(parts.length ? ["DESCRIPTION:" + icsEscape(parts.join("\n\n"))] : []),
    ...(link ? ["URL:" + link] : []),
    "END:VEVENT",
  ];
}

function calendar(events: string[][], extraHeader: string[] = []) {
  const lines = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//AW-appen//SV", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
    ...extraHeader,
    ...events.flat(),
    "END:VCALENDAR",
  ];
  return new Response(lines.map(fold).join("\r\n") + "\r\n", {
    headers: {
      ...CORS,
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": 'inline; filename="aw.ics"',
      "Cache-Control": "no-store",
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  const id = new URL(req.url).searchParams.get("id");

  try {
    const site = await siteUrl();

    // Ett enskilt förslag
    if (id !== null) {
      if (!UUID.test(id)) return text("Ogiltigt förslag.", 400);
      const [p] = await rest<Proposal[]>(`aw_proposal?id=eq.${id}&select=id,place,starts_at,note,created_by`);
      if (!p) return text("Förslaget finns inte längre.", 404);
      return calendar([eventLines(p, site)]);
    }

    // Prenumerationskalender: alla förslag från i går och framåt
    const since = new Date(Date.now() - 864e5).toISOString();
    const [proposals, rsvps] = await Promise.all([
      rest<Proposal[]>(`aw_proposal?starts_at=gte.${encodeURIComponent(since)}` +
        "&select=id,place,starts_at,note,created_by&order=starts_at.asc"),
      rest<Rsvp[]>("rsvp?proposal_id=not.is.null&select=proposal_id,status"),
    ]);
    const counts = new Map<string, { yes: number; maybe: number }>();
    for (const r of rsvps) {
      const c = counts.get(r.proposal_id) ?? { yes: 0, maybe: 0 };
      if (r.status === "yes") c.yes++;
      if (r.status === "maybe") c.maybe++;
      counts.set(r.proposal_id, c);
    }
    return calendar(
      proposals.map((p) => eventLines(p, site, counts.get(p.id) ?? { yes: 0, maybe: 0 })),
      [
        "X-WR-CALNAME:AW",
        "X-WR-CALDESC:" + icsEscape("Alla AW-förslag från AW-appen" + (site ? " – " + site : "")),
        "X-WR-TIMEZONE:Europe/Stockholm",
        "REFRESH-INTERVAL;VALUE=DURATION:PT1H",
        "X-PUBLISHED-TTL:PT1H",
      ],
    );
  } catch (e) {
    console.error(e);
    return text("Kunde inte skapa kalendern.", 500);
  }
});
