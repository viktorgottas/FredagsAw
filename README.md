# Fredags-AW – anmälningssida

Enkel anmälningssida för AW på Churchill Arms, Tulegatan 21 (fredag 16 oktober, från 16.30).
Statisk sida (`index.html` + `aw-poster.jpg`) på GitHub Pages med Supabase som databas.
Ingen inloggning, inget byggsteg.

## 1. Skapa Supabase-projektet

1. Gå till <https://supabase.com>, logga in (t.ex. med GitHub) och klicka **New project**.
2. Välj organisation, ge projektet ett namn (t.ex. `fredagsaw`), välj ett databaslösenord
   (spara det, men sidan behöver det inte) och region **Stockholm (eu-north-1)** eller närmaste EU-region.
   Plan: **Free**. Klicka **Create new project** och vänta någon minut.
3. Öppna **SQL Editor** i vänstermenyn → **New query**, klistra in hela innehållet i
   [`supabase.sql`](supabase.sql) och klicka **Run**. Det ska stå "Success. No rows returned".

SQL:en skapar tabellen `rsvp` (id, name, status, token, created_at) och slår på Row Level Security:

- alla får **läsa** (id, namn, status, tid) och **lägga till** anmälningar,
- **ändra/ta bort** går bara om headern `x-rsvp-token` matchar radens token,
- kolumnen `token` går **inte** att läsa via API:t, så ingen kan sno någon annans token.

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

1. Committa och pusha (`index.html`, `aw-poster.jpg`, `.nojekyll`) till GitHub.
2. I repot på GitHub: **Settings → Pages**. Under *Build and deployment*:
   **Source: Deploy from a branch**, **Branch: `master`**, mapp **`/ (root)`** → **Save**.
3. Efter någon minut finns sidan på `https://<användarnamn>.github.io/<repo>/`.

## Hur det fungerar

- Varje besökare får en slumpad token i `localStorage`. Den skickas med när man sparar
  och som header när man ändrar eller tar bort sin anmälan.
- Samma webbläsare kan ändra sitt svar så många gånger den vill; byter man telefon/webbläsare
  blir det en ny anmälan (den gamla kan då inte ändras därifrån).
- Listan uppdateras var 10:e sekund (och direkt när man kommer tillbaka till fliken).
- Namn sätts med `textContent`, så HTML i namn visas bara som text.

## Rensa efteråt

Ta bort alla anmälningar: kör `delete from public.rsvp;` i SQL Editor.
Ta bort en enskild (t.ex. skräp): **Table Editor → rsvp**, markera raden → Delete.
