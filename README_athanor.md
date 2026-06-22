# Athanor — Setup Supabase

Athanor è una web app (singolo file `athanor.html`) per la crescita personale e la trasformazione interiore, con autenticazione e database su **Supabase**.

L'app funziona in due modalità:

- **Demo (locale)** — senza configurazione: i dati restano in memoria e si azzerano al refresh. Utile per provare subito.
- **Cloud (Supabase)** — con login Google/Apple: voci del diario, blocchi e progressi vengono salvati su Postgres e sincronizzati su ogni dispositivo.

---

## 1. Crea il progetto Supabase

1. Vai su [supabase.com](https://supabase.com) e crea un nuovo progetto (piano gratuito sufficiente).
2. Attendi che il database sia pronto (~2 minuti).

## 2. Esegui lo schema del database

1. Nel pannello Supabase apri **SQL Editor → New query**.
2. Incolla l'intero contenuto di `athanor_supabase_schema.sql` e premi **Run**.

Questo crea le tabelle `profiles`, `blocks`, `entries`, le policy di **Row Level Security** (ogni utente vede solo i propri dati), il trigger che genera il profilo alla registrazione e la view `opera_progress`.

## 3. Abilita il login Google e Apple

1. **Authentication → Providers → Google**: attivalo e inserisci Client ID e Secret (da Google Cloud Console → OAuth consent screen + credenziali).
2. **Authentication → Providers → Apple**: attivalo e inserisci le credenziali Apple (Services ID, Team ID, Key). *Opzionale per iniziare — puoi attivare solo Google.*
3. **Authentication → URL Configuration**: in *Site URL* e *Redirect URLs* inserisci l'indirizzo dove ospiti l'app (es. `http://localhost:5500` in locale, o il tuo dominio).

## 4. Inserisci le credenziali nell'app

1. In Supabase apri **Project Settings → API** e copia:
   - **Project URL** (es. `https://abcdxyz.supabase.co`)
   - **anon / public key** (la chiave pubblica — sicura lato client)
2. Apri `athanor.html`, trova in cima allo `<script>` queste due righe e sostituisci i placeholder:

   ```js
   const SUPABASE_URL      = "INSERISCI_QUI_IL_TUO_SUPABASE_URL";
   const SUPABASE_ANON_KEY = "INSERISCI_QUI_LA_TUA_SUPABASE_ANON_KEY";
   ```

> ⚠️ Usa **solo** la chiave *anon/public*. Non inserire mai la `service_role` key in codice lato client: ha privilegi completi e bypassa la Row Level Security.

## 5. Avvia l'app

Apri `athanor.html` da un piccolo server locale (necessario per il redirect OAuth), ad esempio:

```bash
# Python
python -m http.server 5500
# oppure Node
npx serve .
```

Poi visita `http://localhost:5500/athanor.html`. Vedrai la schermata di login. Dopo l'accesso, l'onboarding crea il primo percorso e ogni voce del diario viene salvata nel cloud.

Se apri il file direttamente (doppio click, senza server) o non hai configurato Supabase, l'app parte automaticamente in **modalità demo**.

---

## Struttura dati

| Tabella    | Contenuto                                                                 |
|------------|---------------------------------------------------------------------------|
| `profiles` | Un profilo per utente: nome, obiettivo, tempo giornaliero, streak, metriche |
| `blocks`   | Blocchi interiori, ciascuno in una fase alchemica: `nigredo` (nero) → `albedo` (bianco) → `rubedo` (rosso) |
| `entries`  | Voci del Diario Alchemico: evento, emozione, intensità, interpretazione, trasmutazione, azione, parole chiave |

La view `opera_progress` calcola la percentuale dell'**Opera Alchemica** combinando l'avanzamento dei blocchi (65%) e l'attività sul diario (35%).

## Verso la produzione (App Store / Google Play)

Questo prototipo web condivide la stessa architettura dati pensata per una futura app nativa:

- **React Native (Expo)** o **Flutter** come client mobile.
- `@supabase/supabase-js` (o `supabase_flutter`) con lo **stesso schema SQL** già pronto.
- Auth Google/Apple, notifiche push (Expo Notifications / FCM), e modalità offline con sincronizzazione.

Lo schema, le policy RLS e la logica dell'Opera Alchemica restano identici: cambia solo il livello di presentazione.
