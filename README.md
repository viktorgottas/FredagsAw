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
- **ändra/ta bort** sitt svar, eller **ändra/ta bort** sitt förslag, går bara om headern
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
- Förslagen sorteras efter datum (nästa AW överst) och får etiketter: Nästa AW / I dag! / Pågår nu,
  Nytt / Senast inlagd, Flest kommer, Fullt ös (6+) och Ensamvarg (bara en kommer).
- Förslaget med flest "kommer" får etiketten **Flest kommer**, och förslag som tillkommit sedan
  ditt förra besök märks **Nytt**.
- Varje förslag har knapparna **Dela** (delningsmenyn i mobilen, eller kopiera länk), **Kalender**
  (iPhone/Apple, Google eller Outlook) och **Hitta hit** (Google Maps). Delade länkar går direkt
  till förslaget.
- Under varje förslag finns **kommentarer** (max 280 tecken). Man kan ta bort sina egna;
  admin kan ta bort alla.
- Direkt efter att man lagt ett förslag visas knappen **Dela i Snap-gruppen** (öppnar delningsmenyn;
  välj Snapchat → gruppen). Utan delningsmeny kopieras texten i stället.
- Sidan kan läggas på hemskärmen som en app; en guide för iPhone (Safari) och Android (Chrome)
  finns längst ner och döljs när sidan redan körs som app.
- **Nedräkning** på varje förslag ("om 2 dagar 4 tim", "Pågår nu!") och ölkonfetti när man
  svarar "Jag kommer".
- **Väder** för AW-tiden (Open-Meteo, Stockholm, upp till 16 dagar fram; ingen nyckel behövs),
  och en slumpad rolig kommentar (regn/kallt/snö/åska: "vi håller oss inne"-skämt, sol: uteservering).
- **🎲 Slumpa** bredvid "Var?" slumpar en bar innanför tullarna från listan `BARS` i `index.html`
  plus ställen ni redan föreslagit. Ändra listan fritt.
- **Pris på en stor stark** sparas per ställe (`aw_place_price`, via `aw_set_price`) och visas på alla
  förslag på samma ställe och som tips i formuläret. Vem som helst kan lägga in eller ändra priset.
- **Vem bjuder på första rundan?** slumpas (i databasen, `aw_draw_buyer`) bland dem som kommer,
  när minst två har svarat ja. Alla ser samma namn. Kommer nya personer efter slumpningen kan vem
  som helst slumpa om (bland alla som kommer); annars kan bara admin slumpa om.
- **Hemlig plats 🤫**: kryssa i "Hemlig plats" och välj när den avslöjas. Platsen ligger i
  `secret_place` som inte går att läsa via API:t, och avslöjas av `aw_reveal_due()` (pg_cron varje
  minut, och när någon öppnar sidan). Prenumeranter får mejl både när den läggs upp och när den avslöjas – utan platsen, den syns bara i appen.
- **Bilder 📸** kan läggas upp från att AW:n börjat (skalas ner till max 1600 px JPEG, platsdata tas
  bort). Filerna ligger i Storage-bucketen `aw-photos`; borttagna bilder döljs men filen ligger kvar
  i Storage tills du tar bort den där.
- **Minnen** visar de senaste 10 AW:erna som någon gick på, med bilder. **Topplistan** visar
  Stammisar, Idésprutor, Kanske-kungar, Billigaste ölen och Dyraste ölen (från priserna på stor stark). Passerade förslag som ingen svarade ja på raderas.
- Appen har tre flikar längst ner: **AW:er** (flödet med förslag och Minnen), **Föreslå** och
  **Mer** (topplista, mejl/kalender, hemskärmsguide, admin). Länkar: `#foresla`, `#mer`, `#kalender`,
  `#forslag-<id>`. En siffra på AW:er visar nya förslag man inte sett.
- Listan uppdateras var 10:e sekund (och direkt när man kommer tillbaka till fliken).
- Namn sätts med `textContent`, så HTML i namn visas bara som text.

## Kalender (Edge Function)

Funktionen `aw-ics` ger två saker:

- `…/functions/v1/aw-ics?id=<id>` – ett förslag som kalenderfil ("Kalender → iPhone / Apple";
  Safari kan inte öppna kalenderfiler som skapas i sidan).
- `…/functions/v1/aw-ics` – en **prenumerationskalender** med alla kommande förslag. Under
  "Håll dig uppdaterad → Kalender" finns knappar för iPhone/Mac (`webcal://`), Google och Outlook.
  Nya förslag dyker upp automatiskt och ändrad tid/plats uppdateras.

Installera/uppdatera funktionen:

1. Supabase → **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. Döp den till `aw-ics`, ersätt koden med innehållet i
   [`supabase/functions/aw-ics/index.ts`](supabase/functions/aw-ics/index.ts) och klicka **Deploy**.
3. Öppna funktionen → **Details** och stäng av **Verify JWT** (annars kan en vanlig länk inte öppna den) → **Save**.

Utan funktionen laddas kalenderfilen ner i stället (öppna den i Filer).

## Admin: ta bort förslag, kommentarer, bilder, folk och slumpningar

1. Lägg in en admin-kod i Supabase (SQL Editor, byt `HEMLIG-KOD` mot din egen):

   ```sql
   insert into public.aw_admin (code_hash)
   values (encode(sha256(convert_to('HEMLIG-KOD', 'UTF8')), 'hex'));
   ```

2. Tryck **Logga in som admin** längst ner på sidan (eller öppna sidan med `#admin` i slutet av
   adressen) och skriv in koden. Webbläsaren kommer ihåg den; "Logga ut som admin" finns längst ner.
3. Byta kod: `delete from public.aw_admin;` och lägg in en ny enligt steg 1.

Som admin kan du även ändra tid/plats på alla förslag, ta bort någons svar (× på namnet; var det
den som skulle bjuda nollställs slumpningen) och slumpa om eller ta bort "vem bjuder".

Koden lagras bara som hash i databasen och finns aldrig i koden på GitHub.

## E-postnotiser och prenumeration (valfritt)

- **Du** (`notify_email`) får mejl om nya förslag, ändrad tid/plats och nya kommentarer.
- **Alla andra** kan skriva in sin mejl under "Få mejl om nya AW:er" och får då bara mejl om
  nya förslag och ändrad tid/plats. Varje mejl har en avregistreringslänk (`?avregistrera=…`).

Mejltjänst – välj en:

- **Brevo** (gratis 300 mejl/dag) – kan mejla vem som helst utan egen domän. Verifiera din
  avsändaradress under *Senders, Domains & Dedicated IPs → Senders* och skapa en API-nyckel under
  *SMTP & API → API Keys*.
- **Resend** – utan egen domän går mejl bara till kontots egen adress, så prenumeranter kräver en
  verifierad domän.

1. Kör [`epost-notiser.sql`](epost-notiser.sql) i SQL Editor (går att köra flera gånger).
2. Kör med dina värden:

   ```sql
   insert into public.aw_settings (key, value) values
     ('mail_provider', 'brevo'),
     ('brevo_api_key', 'xkeysib-...'),
     ('sender_email',  'din@mejl.se'),
     ('notify_email',  'din@mejl.se'),
     ('site_url',      'https://<användarnamn>.github.io/<repo>/')
   on conflict (key) do update set value = excluded.value;
   ```

**Påminnelse samma dag:** kl. 12 (svensk tid) samma dag som en AW får du och prenumeranterna ett
mejl med tid, plats (inte för hemliga platser), vilka som kommer och vem som bjuder. Körs av pg_cron
var 15:e minut (`aw_send_reminders`). Byt tid: `reminder_hour` i `aw_settings`. Kontrollera att
schemat finns: `select jobname, schedule from cron.job;`

Se prenumeranter: `select email, created_at from public.aw_subscriber;`
Stänga av alla mejl: `delete from public.aw_settings where key in ('brevo_api_key', 'resend_api_key');`

## Rensa efteråt

Ta bort allt: kör `delete from public.aw_proposal; delete from public.rsvp;` i SQL Editor (kommentarer följer med förslagen).
Ta bort enskilda rader (t.ex. skräp): **Table Editor → aw_proposal / rsvp**, markera raden → Delete.
