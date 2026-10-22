// Supabase Edge Function "aw-ics": serverar ett förslag som kalenderfil (.ics),
// så att iPhone/Mac visar "Lägg till i Kalender" när länken öppnas.
//
// Anrop: https://<projekt>.supabase.co/functions/v1/aw-ics?id=<förslagets id>
// Viktigt: stäng av "Verify JWT" för funktionen, annars kan en vanlig länk inte öppna den.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "*" };

type Proposal = { id: string; place: string; starts_at: string; note: string | null };

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  const id = new URL(req.url).searchParams.get("id") ?? "";
  if (!UUID.test(id)) return text("Ogiltigt förslag.", 400);

  try {
    const [p] = await rest<Proposal[]>(`aw_proposal?id=eq.${id}&select=id,place,starts_at,note`);
    if (!p) return text("Förslaget finns inte längre.", 404);

    let site = "";
    try {
      const s = await rest<{ value: string }[]>("aw_settings?key=eq.site_url&select=value");
      site = s[0]?.value ?? "";
    } catch { /* inställningen är valfri */ }
    const link = site ? site + "#forslag-" + p.id : "";

    const start = new Date(p.starts_at).getTime();
    const description = (p.note ? p.note + "\n\n" : "") + (link ? "Svara här: " + link : "");
    const lines = [
      "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//AW-appen//SV", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
      "BEGIN:VEVENT",
      "UID:" + p.id + "@aw-appen",
      "DTSTAMP:" + icsDate(Date.now()),
      "DTSTART:" + icsDate(start),
      "DTEND:" + icsDate(start + 3 * 3600 * 1000),
      "SUMMARY:" + icsEscape("AW: " + p.place),
      "LOCATION:" + icsEscape(p.place),
      ...(description ? ["DESCRIPTION:" + icsEscape(description)] : []),
      ...(link ? ["URL:" + link] : []),
      "END:VEVENT", "END:VCALENDAR",
    ];
    return new Response(lines.map(fold).join("\r\n") + "\r\n", {
      headers: {
        ...CORS,
        "Content-Type": "text/calendar; charset=utf-8",
        "Content-Disposition": 'inline; filename="aw.ics"',
        "Cache-Control": "no-store",
      },
    });
  } catch (e) {
    console.error(e);
    return text("Kunde inte skapa kalenderfilen.", 500);
  }
});
