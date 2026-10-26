# Brand voice: Italian (it)

Italian for `lib/l10n/app_it.arb`. The rules all languages share are in `translating.md`; this guide holds only what is Italian.

**Binding, set by the product owner:**
- Address the reader as **tu**: «Tocca», «Inserisci», «Scegli», «il tuo/la tua».
- Chat = **chat**, room = **stanza**, community = **comunità**. Never «gruppo», «canale», «spazio» or «community».
- **Zuno**, **Matrix**, **Android**, **iOS**, **Google** and **Apple** take no article: «Zuno crittografa i tuoi messaggi», «la versione di Zuno».
- `languageNativeName` → «Italiano».

---

## 1. Glossary

### 1.1 Brand-voice words

| English | it | Notes |
|---|---|---|
| chat (one-to-one) | la chat · le chat | "New chat" → «Nuova chat». The "Chats" tab → «Chat». Never «conversazione» as the product noun. |
| room (group chat) | la stanza · le stanze | Never «sala». |
| community | la comunità | Never «server». |
| "Group with {names}" | «Chat con {names}» | |
| device | il dispositivo | Never «telefono». |
| recovery code | il codice di recupero | Never «chiave» or «password». |
| recovery | il recupero | "Set up recovery" → «Configura il recupero». |
| sign in | Accedi / accedere · l’accesso | "New sign-in" → «Nuovo accesso». A signed-in device → «dispositivo connesso». |
| sign out | Esci / uscire · la disconnessione | "Sign out everywhere else" → «Esci da tutti gli altri dispositivi». |
| sign up, sign-up code | Crea account · la registrazione · il codice di registrazione | Push registration is «registrazione push». |
| server, homeserver | il server | |

### 1.2 People

| English | it | Notes |
|---|---|---|
| person, people | la persona · le persone | Grammatically feminine, so it forces no gender. |
| user / member | l’utente / il membro | "Unknown user" → «Utente sconosciuto». |
| You (own name on tiles and the map) | Tu | |
| Someone / Anyone / Nobody / Everyone | Qualcuno / Chiunque / Nessuno / Tutti | |

### 1.3 Messaging

| English | it | Notes |
|---|---|---|
| message | il messaggio | Composer placeholder "Message" → «Messaggio». |
| send | Invia / inviare (inviato) | "Not sent" → «Non inviato». "Sending…" → «Invio in corso…». |
| reply | Rispondi · la risposta | "Replying to {name}" → «Risposta a {name}». |
| reaction, react | la reazione · reagire | |
| edit, edited | Modifica · modificato | The "edited" marker agrees with «messaggio». |
| delete | Elimina / eliminare (eliminato) | "Message deleted" → «Messaggio eliminato». Never «cancella». |
| remove (an item or person) | Rimuovi / rimuovere | |
| seen, seen by | Visualizzato · Visto da {people} | "Not seen yet" → «Non ancora visualizzato». |
| typing | sta scrivendo… | "{name} is typing…" → «{name} sta scrivendo…». "Several people are typing…" → «Più persone stanno scrivendo…». |
| mention | menzionare · la menzione | "Mentions only" → «Solo menzioni». |
| attachment, voice message | l’allegato · il messaggio vocale | |
| photo / video / file | la foto / il video / il file | |
| media, item | i contenuti multimediali · l’elemento | The "Media" heading → «Contenuti multimediali». "Delete 3 items?" → «Eliminare 3 elementi?». |
| caption, gallery | la didascalia · la galleria | iOS Photos app → «Foto». |
| history | la cronologia | |
| record, upload, download, reload | registrare · inviare · scaricare · ricaricare | "Uploading…" → «Invio in corso…». "Downloading…" → «Download in corso…». «Caricamento…» is Loading only. |
| emoji, verification emoji | l’emoji · le immagini | |

### 1.4 Calls

| English | it | Notes |
|---|---|---|
| call, voice call, video call | la chiamata · la chiamata vocale · la videochiamata | Button "Call" → «Chiama». |
| ring, ringtone, full screen | squillare · la suoneria · schermo intero | |
| incoming / missed / ongoing call | chiamata in arrivo / persa / in corso | "Missed call from {name}" → «Chiamata persa da {name}». |
| Accept / Decline | Accetta / Rifiuta | Also for invites and requests. |
| hang up, End call | Termina chiamata | Both. |
| join (a call) | Partecipa / partecipare alla chiamata | |
| speaker, mute, unmute | l’altoparlante · Disattiva microfono · Attiva microfono | "Muted" → «Microfono disattivato». "{name} is muted" → «Microfono di {name} disattivato». |
| mute someone, remove from a call | disattivare il microfono di {name} · Rimuovi dalla chiamata / rimuovere dalla chiamata | Call moderation. "{name} muted you" → «{name} ha disattivato il tuo microfono». "{name} removed you from the call." → «{name} ha rimosso il tuo account dalla chiamata.» "You were removed from this call." → «Il tuo account è stato rimosso da questa chiamata.» As in the room update (§1.11), «ti ha rimosso» would agree with the reader. |
| camera, microphone | la fotocamera · il microfono | |
| connection, connecting, reconnecting | la connessione · Connessione in corso… · Riconnessione in corso… | "Weak connection" → «Connessione debole». "Poor connection" → «Connessione scarsa». "Calling…" → «Chiamata in corso…». |
| picture-in-picture, minimize | picture in picture · Riduci | |

### 1.5 Security and encryption

| English | it | Notes |
|---|---|---|
| encryption, encrypted, decrypt | la crittografia · crittografato · decrittografare | Never «cifratura» or «cifrato». |
| end-to-end encrypted | con crittografia end-to-end | |
| confirm (a person) | Conferma / confermare | "Confirmed people only" → «Solo persone confermate». |
| approve (own device) | Approva / approvare | |
| verify, verification | verificare · la verifica | |
| security details | i dati di sicurezza | |
| key, room keys | la chiave · le chiavi delle stanze | |
| backup, key backup, restore | il backup · il backup delle chiavi · ripristinare | |
| security key, security phrase, recovery key | la chiave di sicurezza · la frase di sicurezza · la chiave di recupero | |
| cross-signing, secret storage | la firma incrociata · l’archivio segreto | |
| session | la sessione | |
| unlock, trust | sbloccare · fidarsi | |
| scan, QR code, code | Scansiona · il codice QR · il codice | "Scan code" → «Scansiona codice». A bare «codice» is never a password. |
| screenshot, screen recording, screen sharing | lo screenshot · la registrazione dello schermo · la condivisione dello schermo | |
| block | Blocca / sbloccare | |
| rooted device, compromised device | dispositivo con root · dispositivo compromesso | |
| clipboard, password manager | gli appunti · il gestore di password | |
| incognito keyboard | Tastiera in incognito | |
| Cryptography | la crittografia | |
| raw (security key), vouch for | non formattata · convalidare | |

### 1.6 Account, server and membership

| English | it | Notes |
|---|---|---|
| account, password | l’account · la password | "Wrong password." → «Password errata.» |
| username, display name | il nome utente · il nome visualizzato | |
| profile, profile photo | il profilo · la foto del profilo | |
| email address | l’indirizzo email | |
| invite | Invita · l’invito | The "Invited" badge → «Invito inviato». |
| withdraw (an invitation) | ritirare l’invito | "{sender} withdrew your invitation" → «{sender} ha ritirato il tuo invito». |
| join (a room or community) | Entra / entrare | "{people} joined" → «Nuovo membro: {people}» (§2.4). |
| request, ask to join | la richiesta · Chiedi di entrare | "Let in" → «Accetta». "Withdraw" → «Ritira richiesta». |
| leave | Esci / lasciare | "{people} left" → «{people} ha lasciato». |
| remove (a person) | Rimuovi / rimuovere | The kick action. |
| ban | Banna / revoca il ban | "Banned" heading → «Persone bannate». |
| report | Segnala · la segnalazione | Reasons: «Molestie», «Contenuti illegali», «Spam», «Altro motivo». |
| public / private | pubblica / privata | Feminine, agreeing with stanza and comunità. |
| topic, description, address, ID | l’argomento · la descrizione · l’indirizzo · l’ID | Room alias → «l’indirizzo della stanza». |
| hostname | il nome del server | |

### 1.7 Roles and permissions

| English | it | Notes |
|---|---|---|
| admin, moderator, owner | amministratore · moderatore · proprietario | Role badges, generic masculine. |
| role, member, read-only, view only | il ruolo · Membro · Sola lettura · Solo visualizzazione | |
| permission (room or OS), access | l’autorizzazione · l’accesso | "Roles & permissions" → «Ruoli e autorizzazioni». |

### 1.8 Notifications and push

| English | it | Notes |
|---|---|---|
| notification, test notification | la notifica · la notifica di prova | |
| alert | l’avviso | "Security alerts" → «Avvisi di sicurezza». As iOS «Avvisi critici»; never «allerta». |
| mute / unmute (a chat's notifications) | Disattiva notifiche / Riattiva notifiche | |
| push, push target, push key | il push · la destinazione push · la chiave push | "push notifications" → «notifiche push». |
| registration (push) | la registrazione / registrare (registrato) | |
| delivery, background sync | la consegna · la sincronizzazione in background | "Delivery method" → «Metodo di consegna». |
| battery use: Unrestricted / Optimized / Restricted | utilizzo della batteria: Senza restrizioni / Ottimizzato / Con restrizioni | Android's labels. |
| Data Saver, Autostart | Risparmio dati · Avvio automatico | |
| distributor | il distributore | |
| Google services / Google Play services | i servizi Google / Google Play Services | |
| Apple push | il push di Apple | |
| gateway, bridge, token | il gateway · il bridge · il token | |
| diagnostics | la diagnostica | |
| notification category, notification shade | la categoria di notifiche · l’area notifiche | |
| lock screen | la schermata di blocco | |
| quiet, sound, vibration | silenziose · il suono · la vibrazione | "Message tone" → «Suono dei messaggi». |
| standby bucket | il gruppo di standby | |

### 1.9 Location

| English | it | Notes |
|---|---|---|
| location, live location | la posizione · la posizione in tempo reale | |
| share, start / stop sharing | Condividi · Avvia / Interrompi la condivisione | Also for sharing files. |
| approximate, maps app | approssimativa · l’app di mappe | |

### 1.10 Settings, storage and data

| English | it | Notes |
|---|---|---|
| Settings | le Impostazioni | Zuno's, Android's and iOS's. |
| storage, data, cache | lo spazio di archiviazione · i dati · la cache | "Clear cache" → «Svuota cache». |
| theme: Dark / Light / Follow system | Scuro / Chiaro / Predefinito di sistema | |
| Appearance / About / Advanced, version, build | Aspetto / Informazioni / Avanzate · la versione · la build | |
| feedback, crash reports | il feedback · i report sugli arresti anomali | "Send feedback" → «Invia feedback». |
| donate, privacy, Privacy policy, Terms | fare una donazione · la privacy · Informativa sulla privacy · Termini | |
| app, home screen, shortcut, launcher | l’app · la schermata Home · la scorciatoia · il launcher | «app» is feminine. |
| recent apps, app switcher | le app recenti · il selettore app | |
| Open source licenses, Source code | Licenze open source · Codice sorgente | |

### 1.11 Settled phrases

| English | it | Notes |
|---|---|---|
| Asking to join (admin heading) | Richieste di accesso | "Asking to join {name}" → «Richieste di accesso a «{name}»». |
| Ask to join (subtitle) / Asks to join | Chiedono di entrare / Chiede di entrare | The button stays «Chiedi di entrare». |
| Let them ask (setting) | Consenti le richieste | |
| Joined (label on a public room or community) | Ne fai già parte | |
| N other(s) | {count} altra persona · {count} altre persone | |
| asleep (device) / suspended (app) | in standby / sospesa | «sospesa» agrees with «l’app». |
| Call rang / ringing | La chiamata ha squillato / squilla | |
| Hidden message | il messaggio nascosto | Never «segreto». |
| Secure backup (screen) | «Recupero» | |
| Welcome to Zuno | Zuno ti dà il benvenuto | «Benvenuto» would force a gender. |
| {name} is confirmed | Hai confermato {name} | |
| Invited you to {room} | Invito a «{room}» | «Ti ha invitato» would agree with the reader. |
| {name} invited you (to …) | {name} ti invita (in …) | The present tense avoids «ti ha invitato/a». |
| Confirmed / Scanned / Approved (titles after a check) | Conferma completata / Scansione completata / Dispositivo approvato | |
| Chat / Room / Community info | Informazioni sulla chat / sulla stanza / sulla comunità | |
| Room / Community defaults | Impostazioni predefinite della stanza / della comunità | |
| "You and {name} are…" | Recast so the verb is not plural «voi»: «Posizione in tempo reale condivisa da te e {name}». | |
| Make {people} an admin / You are now an admin (room updates) | {sender} ha assegnato il ruolo «Amministratore» a {people} / Ora hai il ruolo «Amministratore» | Every role the same way, with its exact label: «nominare amministratore» would agree with the person. |
| You joined / joined and left (room updates) | Ora fai parte della stanza / {people} ha lasciato poco dopo l’ingresso | «Sei entrato/a» and «è entrato/a» would agree with the person. |
| {sender} invited / removed / banned you (room updates) | {sender} ti ha inviato un invito / {sender} ha rimosso il tuo account dalla stanza / Hai ricevuto un ban da {sender} | Past tense, as in every room update, with no participle agreeing with «ti». |
| character(s), link, check mark | il carattere · i caratteri · il link · il segno di spunta | |

### 1.12 UI actions

| English | it |
|---|---|
| Cancel / Save / Saved | Annulla / Salva / Salvato |
| Delete / Remove | Elimina / Rimuovi |
| Copy / Copied / Share | Copia / Copiato / Condividi |
| Send / Continue / Continue anyway | Invia / Continua / Continua comunque |
| Done / Retry / Try again | Fine / Riprova / Riprova |
| Close / Dismiss / Open / Open settings | Chiudi / Ignora / Apri / Apri impostazioni |
| Turn on / Turn off · On / Off | Attiva / Disattiva · Attivo / Disattivato |
| Allow / Not now / Skip | Consenti / Non ora / Salta |
| Confirm / Approve | Conferma / Approva |
| Create / Start / Get started | Crea / Avvia / Inizia |
| Edit / Change / Review | Modifica / Cambia / Controlla |
| Back / Stop / Play | Indietro / Interrompi / Riproduci |
| Read more / Show less | Leggi di più / Mostra meno |
| Mark as read / Unread | Segna come letto / Non letti |
| Refresh / Search / Start over | Aggiorna / Cerca / Ricomincia |

### 1.13 Status words

| English | it |
|---|---|
| Loading… / Sending… / Waiting… | Caricamento… / Invio in corso… / In attesa… |
| Checking… / Searching… | Verifica in corso… / Ricerca in corso… |
| Failed | Non riuscito |
| Not set / Unknown / None / Never | Non impostato / Sconosciuto / Nessuno / Mai |
| Not available / Yes / No | Non disponibile / Sì / No |
| Just now / Today / Yesterday / Coming soon | Adesso / Oggi / Ieri / Disponibile a breve |

---

## 2. Italian rules

### 2.1 Register
- «tu» throughout, usually left implicit: «Tocca per riprovare», «Il tuo account è stato eliminato». Never «Lei», never «voi».
- "tap" → «tocca», "type" → «scrivi», "enter" → «inserisci», "choose/pick" → «scegli», "pull down" → «scorri verso il basso».

### 2.2 Forms

| Where | Form | Example |
|---|---|---|
| Buttons, menu items, tabs, tooltips, switches, row labels that act | Imperative (tu), as Android and iOS do | «Elimina account», «Salva», «Attiva altoparlante» |
| Body text, hints, the next step in an error | Imperative (tu) | «Tocca per riprovare.» |
| Titles that name something | Noun | «Impostazioni della stanza», «I tuoi dispositivi» |
| Titles that instruct | Imperative | «Salva il tuo codice di recupero» |
| Confirmation titles ("Delete X?") | Infinitive + «?» | «Eliminare il tuo account?» |
| Progress labels | Noun + «in corso…» or noun + «…» | «Creazione dell’account in corso…», «Caricamento…» |
| Success snack bars | Participle | «Password cambiata», «Segnalazione inviata» |

Statement and first-person buttons: «Corrispondono», «Non corrispondono», «Sì, termina», «No, interrompi», «Ho già un codice».

### 2.3 Typography
- Apostrophe: the typographic ’ (U+2019) everywhere: «l’app», «un’altra». Never the straight '.
- Capital E with grave accent is «È», never «E’».
- Quotes: « » with no inner spaces: `«{name}»`.
- Colons stay exactly as in the English.
- Weekday and month names are lowercase.

### 2.4 Names
- Subject names take verbs with «avere», whose participle never agrees: «{people} ha lasciato», «{sender} ha invitato {people}», «{people} ha chiesto di entrare».
- Never a participle with «essere» or an adjective that agrees with a person, the reader included: no «è entrato/a», «connesso/a», «invitato/a», «benvenuto/a». Recast with a noun or an «avere» verb: «Nuovo membro: {people}», «Accesso effettuato», «Hai bloccato {name}».
- "With {name}" → «Con {name}».
- "they" → «questa persona» or drop the subject: "once they join" → «quando questa persona entra».

### 2.5 Fixed phrases
- Error pattern: «Impossibile inviare il messaggio. Controlla la connessione e riprova.»
- "Check your connection and try again." → «Controlla la connessione e riprova.»
- "Pull down to try again." → «Scorri verso il basso per riprovare.»
- "Too many attempts." → «Troppi tentativi.» · "Something went wrong." → «Si è verificato un problema.»
- "Nobody can undo this." → always «Nessuno può annullare questa azione.»
- Never «Ci dispiace», «Purtroppo», «con successo» or «sicuro al 100%».

### 2.6 Numbers, dates and units
- "{date} at {time}" → «{date} alle {time}» · "Until {time}" → «Fino alle {time}» · "{days} days ago" → «{days} giorni fa» · "{page} of {total}" → «{page} di {total}».
- Italian `one` is exactly 1.

### 2.7 Ordinals
`securityOrdinal` precedes «parola» (feminine): `{n, select, 1{1ª} 2{2ª} 3{3ª} other{{n}ª}}`. `settingsRecoveryWordLabel` → «{position} parola». `settingsRecoveryConfirmBody` → «Scrivi la {first} e la {second} parola della copia salvata.»

### 2.8 Platform labels
- Android and iOS both call Settings **Impostazioni**: "Settings → General → Language & Region" → «Impostazioni → Generali → Lingua e zona»; "Settings → Apps → Zuno → Language" → «Impostazioni → App → Zuno → Lingua».
- iOS: «Localizzazione», «Privacy e sicurezza», «Schermata di blocco», «Centro Notifiche», «Banner», «Badge», «Suoni», «Mostra anteprime», «Riepilogo programmato», «Avvisi critici», «Notifiche urgenti», «Annuncia notifiche».

---

## 3. Worked examples

| Key | English | it |
|---|---|---|
| `settingsDeleteAccountWarningTitle` | Delete your account? | Eliminare il tuo account? |
| `feedbackNotSent` | Feedback not sent. Check your connection and try again. | Feedback non inviato. Controlla la connessione e riprova. |
| `chatNotSentRetry` | Not sent · Tap to retry | Non inviato · Tocca per riprovare |
| `callsFailureOnAnotherDevice` | You are in this call on another device. Hang up there to join here. | Partecipi già a questa chiamata da un altro dispositivo. Termina la chiamata lì per partecipare da qui. |
| `settingsAccountPasswordChanged` | Password changed | Password cambiata |
| `blockingTitle` | Block {name}? | Bloccare {name}? |
| `matrixStateNameChanged` | `{sender} changed the room name to \"{name}\"` | `{sender} ha cambiato il nome della stanza in «{name}»` |
| `chatDeleteTitle` | `{count, plural, one{Delete message?} other{Delete {count} items?}}` | `{count, plural, one{Eliminare il messaggio?} other{Eliminare {count} elementi?}}` |
| `matrixInvitePeopleInvited` | `{count, plural, other{{count} people invited}}` | `{count, plural, one{{count} persona invitata} other{{count} persone invitate}}` |
| `permissionsPhotoLibraryAddUsage` | Zuno saves photos and videos to your library only when you tap Save. | Zuno salva foto e video nella tua libreria solo quando tocchi «Salva». |
