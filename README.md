# AW – var och när?

Enkel sida där gänget föreslår var och när nästa AW blir och svarar
**Jag kommer / Kanske / Kan inte** på varje förslag. Alla med länken ser svaren live.
Statisk sida (`index.html` + `aw-poster.jpg`) på GitHub Pages med Supabase som databas.
Ingen inloggning, inget byggsteg.

## 1. Skapa Supabase-projektet

1. Gå till <https://supabase.com>, logga in (t.ex. med GitHub) och klicka **New project**.
2. Välj organisation, ge projektet ett namn (t.ex. `fredagsaw`), välj ett databaslösenord
   (spara det, men sidan behöver det inte) och region **Stockholm (eu-north-1)** eller närmaste EU-region.
   Plan: **Free**. Klicka **Create new project** och vänta någon minut.
3. Öppna **SQL Editor** i vänstermenyn → **New query**, klistra in hela innehållet i
   [`supabase.sql`](supabase.sql) och klicka **Run**. Det ska stå "Success. No rows returned".

SQL:en skapar tabellerna `aw_proposal` (förslag: ställe, tid, kommentar, vem) och `rsvp`
(svar per förslag) och slår på Row Level Security:

- alla får **läsa** och **lägga till** förslag och svar,
- **ändra/ta bort** sitt svar, eller **ta bort** sitt förslag, går bara om headern
  `x-rsvp-token` matchar radens token (tas ett förslag bort försvinner svaren med),
- kolumnen `token` går **inte** att läsa via API:t, så ingen kan sno någon annans token.

**Uppgradera från första versionen:** kör bara hela `supabase.sql` igen. Den går att köra flera gånger.

## 2. Hämta URL och nyckel

I Supabase: **Project Settings** (kugghjulet) → **Data API** / **API Keys**:

- **Project URL** – ser ut som `https://abcdefghijkl.supabase.co`
- **anon public**-nyckeln (under fliken *Legacy API keys*, börjar med `eyJ…`) **eller** den nyare
  **publishable**-nyckeln (`sb_publishable_…`). Båda fungerar.

Använd **aldrig** `service_role`- eller `secret`-nyckeln på sidan.

Klistra in dem överst i skriptet i `index.html`:

```js
const SUPABASE_URL = "https://abcdefghijkl.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOi...";
```

Anon-/publishable-nyckeln är gjord för att synas publikt – skyddet ligger i policyerna ovan.

## 3. Lägg ut på GitHub Pages

1. Committa och pusha alla filer (`index.html`, `aw-poster.jpg`, ikonerna, `manifest.webmanifest`, `.nojekyll`).
2. I repot på GitHub: **Settings → Pages**. Under *Build and deployment*:
   **Source: Deploy from a branch**, **Branch: `master`**, mapp **`/ (root)`** → **Save**.
3. Efter någon minut finns sidan på `https://<användarnamn>.github.io/<repo>/`.

## Hur det fungerar

- Varje besökare får en slumpad token i `localStorage`. Den skickas med när man sparar
  och som header när man ändrar eller tar bort sin anmälan.
- Samma webbläsare kan ändra sina svar så många gånger den vill; byter man telefon/webbläsare
  blir det nya svar (de gamla kan då inte ändras därifrån).
- Tider tolkas och visas alltid i svensk tid. Förslag ligger kvar hela sin dag och tas sedan bort
  automatiskt (sidan anropar `cleanup_past_proposals()` när någon öppnar den; svaren följer med).
- Senast tillagda förslaget visas överst.
- Förslaget med flest "kommer" får etiketten **Flest kommer**, och förslag som tillkommit sedan
  ditt förra besök märks **Nytt**.
- Varje förslag har knapparna **Dela** (delningsmenyn i mobilen, eller kopiera länk), **Kalender**
  (.ics-fil) och **Hitta hit** (Google Maps). Delade länkar går direkt till förslaget.
- Under varje förslag finns **kommentarer** (max 280 tecken). Man kan ta bort sina egna;
  admin kan ta bort alla.
- Sidan kan läggas på hemskärmen som en app (Safari: Dela → Lägg till på hemskärmen).
- Listan uppdateras var 10:e sekund (och direkt när man kommer tillbaka till fliken).
- Namn sätts med `textContent`, så HTML i namn visas bara som text.

## Admin: ta bort vilket förslag eller vilken kommentar som helst

1. Lägg in en admin-kod i Supabase (SQL Editor, byt `HEMLIG-KOD` mot din egen):

   ```sql
   insert into public.aw_admin (code_hash)
   values (encode(sha256(convert_to('HEMLIG-KOD', 'UTF8')), 'hex'));
   ```

2. Tryck **Logga in som admin** längst ner på sidan (eller öppna sidan med `#admin` i slutet av
   adressen) och skriv in koden. Webbläsaren kommer ihåg den; "Logga ut som admin" finns längst ner.
3. Byta kod: `delete from public.aw_admin;` och lägg in en ny enligt steg 1.

Koden lagras bara som hash i databasen och finns aldrig i koden på GitHub.

## E-postnotiser (valfritt)

Ett mejl när någon lägger ett förslag eller skriver en kommentar, via [Resend](https://resend.com)
(gratis upp till 100 mejl/dag).

1. Skapa ett konto på resend.com → **API Keys** → **Create API Key** (Sending access) → kopiera `re_…`.
2. Kör [`epost-notiser.sql`](epost-notiser.sql) i SQL Editor.
3. Kör (med dina värden; mejladressen måste vara den du skapade Resend-kontot med):

   ```sql
   insert into public.aw_settings (key, value) values
     ('resend_api_key', 're_DIN_NYCKEL'),
     ('notify_email',   'din@mejl.se'),
     ('site_url',       'https://<användarnamn>.github.io/<repo>/')
   on conflict (key) do update set value = excluded.value;
   ```

Stänga av: `delete from public.aw_settings where key = 'resend_api_key';`

## Rensa efteråt

Ta bort allt: kör `delete from public.aw_proposal; delete from public.rsvp;` i SQL Editor (kommentarer följer med förslagen).
Ta bort enskilda rader (t.ex. skräp): **Table Editor → aw_proposal / rsvp**, markera raden → Delete.
