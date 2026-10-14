# Brand voice: Italian (it)

How Zuno sounds in Italian: the glossary and style rules behind `lib/l10n/app_it.arb`. Every new English string gets its Italian from here. A string that needs a term this guide lacks adds the term here first.

**Binding, set by the product owner:**
- Address the reader as **tu**: «Tocca», «Inserisci», «Scegli», «il tuo/la tua».
- Chat = **chat**, room = **stanza**, community = **comunità**. They never overlap; «gruppo», «canale», «spazio» and «community» are never used.
- **Zuno** and **Matrix** stay exactly as written, with no article: «Zuno crittografa i tuoi messaggi», «la versione di Zuno».

---

## 1. Glossary

Where a row has two forms, the first is the button/noun form and the second the verb used in body text (§2.2).

### 1.1 Brand-voice words

| English | it | Notes |
|---|---|---|
| chat (one-to-one) | la chat · le chat | "New chat" → «Nuova chat». The "Chats" tab → «Chat». Never «conversazione» as the product noun. |
| room (group chat) | la stanza · le stanze | Never «gruppo», «canale» or «sala». |
| community | la comunità | Never «community», «spazio» or «server». |
| "Group with {names}" | «Chat con {names}» | |
| device | il dispositivo | Never «telefono» or «sessione», even when the description says "phone". |
| recovery code | il codice di recupero | The 12 words. Never «chiave» or «password». |
| recovery | il recupero | "Set up recovery" → «Configura il recupero». |
| sign in | Accedi / accedere · l’accesso | "New sign-in" → «Nuovo accesso». A signed-in device → «dispositivo connesso». |
| sign out | Esci / uscire · la disconnessione | "Sign out everywhere else" → «Esci da tutti gli altri dispositivi». |
| sign up, sign-up code | Crea account · la registrazione · il codice di registrazione | Push registration is «registrazione push» (§1.8); context keeps them apart. |
| server, homeserver | il server | |

### 1.2 People

| English | it | Notes |
|---|---|---|
| person, people | la persona · le persone | Grammatically feminine whatever the person's gender, so it never forces one. |
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
| remove (an item or person) | Rimuovi / rimuovere | Kept apart from delete. |
| seen, seen by | Visualizzato · Visto da {people} | "Not seen yet" → «Non ancora visualizzato». |
| typing | sta scrivendo… | "{name} is typing…" → «{name} sta scrivendo…». "Several people are typing…" → «Più persone stanno scrivendo…». |
| mention | menzionare · la menzione | "Mentions only" → «Solo menzioni». |
| attachment, voice message | l’allegato · il messaggio vocale | |
| photo / video / file | la foto / il video / il file | |
| media, item | i contenuti multimediali · l’elemento | The "Media" heading → «Contenuti multimediali». "Delete 3 items?" → «Eliminare 3 elementi?». |
| caption, gallery | la didascalia · la galleria | iOS Photos app → «Foto». |
| history | la cronologia | |
| record, upload, download, reload | registrare · inviare · scaricare · ricaricare | "Uploading…" → «Invio in corso…». "Downloading…" → «Download in corso…». «Caricamento…» is Loading only. |
| emoji | l’emoji | The verification emoji are «immagini», as in the English. |

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
| camera, microphone | la fotocamera · il microfono | |
| connection, connecting, reconnecting | la connessione · Connessione in corso… · Riconnessione in corso… | "Weak connection" → «Connessione debole». "Calling…" → «Chiamata in corso…». |
| picture-in-picture, minimize | picture in picture · Riduci | |

### 1.5 Security and encryption

| English | it | Notes |
|---|---|---|
| encryption, encrypted, decrypt | la crittografia · crittografato · decrittografare | Never «cifratura» or «cifrato». |
| end-to-end encrypted | con crittografia end-to-end | E2E stays E2E. |
| confirm (a person) | Conferma / confermare | Zuno's word for checking a person. "Confirmed people only" → «Solo persone confermate». |
| approve (own device) | Approva / approvare | Only for your own devices. Never mix with confirm. |
| verify, verification | verificare · la verifica | Only where the English says verify. |
| security details | i dati di sicurezza | |
| key, room keys | la chiave · le chiavi delle stanze | |
| backup, key backup, restore | il backup · il backup delle chiavi · ripristinare | |
| security key, security phrase, recovery key | la chiave di sicurezza · la frase di sicurezza · la chiave di recupero | Advanced screens only; never the 12-word code. |
| cross-signing, secret storage | la firma incrociata · l’archivio segreto | |
| session (Advanced only) | la sessione | Only where the English says "session". |
| unlock, trust | sbloccare · fidarsi | |
| scan, QR code, code | Scansiona · il codice QR · il codice | "Scan code" → «Scansiona codice». A bare «codice» is never a password. |
| screenshot, screen recording, screen sharing | lo screenshot · la registrazione dello schermo · la condivisione dello schermo | |
| block | Blocca / sbloccare | Never for ban. |
| rooted device, compromised device | dispositivo con root · dispositivo compromesso | |
| clipboard, password manager | gli appunti · il gestore di password | |
| incognito keyboard | Tastiera in incognito | |

### 1.6 Account, server and membership

| English | it | Notes |
|---|---|---|
| account, password | l’account · la password | "Wrong password." → «Password errata.» |
| username, display name | il nome utente · il nome visualizzato | |
| profile, profile photo | il profilo · la foto del profilo | One term for photo, picture and avatar. |
| email address | l’indirizzo email | |
| invite | Invita · l’invito | The "Invited" badge → «Invito inviato»: a participle would force a gender (§2.5). |
| join (a room or community) | Entra / entrare | "{target} joined" → «Nuovo membro: {target}» (§2.5). |
| request, ask to join | la richiesta · Chiedi di entrare | "Let in" → «Accetta». "Withdraw" → «Ritira richiesta». |
| leave | Esci / lasciare | "{target} left" → «{target} ha lasciato». |
| remove (a person) | Rimuovi / rimuovere | The kick action. |
| ban | Banna / revoca il ban | "Banned" heading → «Persone bannate». |
| report | Segnala · la segnalazione | Reasons: «Molestie», «Contenuti illegali», «Spam», «Altro motivo». |
| public / private | pubblica / privata | Feminine, agreeing with stanza and comunità. |
| topic, description, address, ID | l’argomento · la descrizione · l’indirizzo · l’ID | |

### 1.7 Roles and permissions

| English | it | Notes |
|---|---|---|
| admin, moderator, owner | amministratore · moderatore · proprietario | Role badges, generic masculine. |
| role, member, read-only | il ruolo · Membro · Sola lettura | |
| permission (room or OS), access | l’autorizzazione · l’accesso | "Roles & permissions" → «Ruoli e autorizzazioni». |

### 1.8 Notifications and push

| English | it | Notes |
|---|---|---|
| notification, test notification | la notifica · la notifica di prova | |
| push, push target, push key | il push · la destinazione push · la chiave push | "push notifications" → «notifiche push». |
| registration (push) | la registrazione / registrare (registrato) | |
| delivery, background sync | la consegna · la sincronizzazione in background | "Delivery method" → «Metodo di consegna». |
| battery use: Unrestricted / Optimized / Restricted | utilizzo della batteria: Senza restrizioni / Ottimizzato / Con restrizioni | Android's labels. |
| Data Saver, Autostart | Risparmio dati · Avvio automatico | |
| distributor, UnifiedPush, ntfy | il distributore · UnifiedPush · ntfy | |
| Google services / Google Play services | i servizi Google / Google Play Services | |
| Apple push | il push di Apple | |
| gateway, bridge, token | il gateway · il bridge · il token | |
| diagnostics | la diagnostica | |
| notification category, notification shade | la categoria di notifiche · l’area notifiche | |
| lock screen | la schermata di blocco | |
| quiet, sound, vibration | silenziose · il suono · la vibrazione | "Message tone" → «Suono dei messaggi». |

### 1.9 Location

| English | it | Notes |
|---|---|---|
| location, live location | la posizione · la posizione in tempo reale | |
| share, start / stop sharing | Condividi · Avvia / Interrompi la condivisione | Also for sharing files. |
| Location Services, Privacy & Security (iOS) | Localizzazione · Privacy e sicurezza | iOS labels. |
| approximate, maps app | approssimativa · l’app di mappe | |

### 1.10 Settings, storage and data

| English | it | Notes |
|---|---|---|
| Settings | le Impostazioni | Zuno's, Android's and iOS's. |
| storage, data, cache | lo spazio di archiviazione · i dati · la cache | "Clear cache" → «Svuota cache». |
| theme: Dark / Light / Follow system | Scuro / Chiaro / Predefinito di sistema | |
| Appearance / About / Advanced, version | Aspetto / Informazioni / Avanzate · la versione | |
| feedback, crash reports | il feedback · i report sugli arresti anomali | "Send feedback" → «Invia feedback». |
| donate, privacy, Privacy policy, Terms | fare una donazione · la privacy · Informativa sulla privacy · Termini | |
| app, home screen, shortcut | l’app · la schermata Home · la scorciatoia | «app» is feminine. |
| recent apps, app switcher | le app recenti · il selettore app | |
| Open source licenses, Source code | Licenze open source · Codice sorgente | License names stay in English. |

### 1.11 Terms settled up front

| English | it | Notes |
|---|---|---|
| hostname | il nome del server | Never left in English. |
| Asking to join (admin heading over others' requests) | Richieste di accesso | "Asking to join {name}" → «Richieste di accesso a «{name}»». |
| Ask to join (subtitle) / Asks to join | Chiedono di entrare / Chiede di entrare | The button stays «Chiedi di entrare». |
| Let them ask (setting) | Consenti le richieste | Not a request the reader sends. |
| Joined (label on a public room or community) | Ne fai già parte | |
| N other(s) | {count} altra persona · {count} altre persone | |
| asleep (device) / suspended (app) | in standby / sospesa | «sospesa» agrees with «l’app». |
| Call rang / ringing | La chiamata ha squillato / squilla | |
| Hidden message | il messaggio nascosto | «segreto» reads as encrypted. |
| Secure backup (screen) | «Recupero» | A legacy name for the Recovery screen: point to it by its title. |
| Welcome to Zuno | Zuno ti dà il benvenuto | «Benvenuto» would force a gender. |
| {name} is confirmed | Hai confermato {name} | A participle would agree with the person. |
| Invited you to {room} | Invito a «{room}» | «Ti ha invitato» would agree with the reader. |
| character(s) | il carattere · i caratteri | |
| link | il link | |
| build (app version) | la build | |
| Cryptography | la crittografia | |
| Room alias | l’indirizzo della stanza | |
| View only | Solo visualizzazione | Apart from «Sola lettura», the role. |
| check mark | il segno di spunta | |
| launcher | il launcher | |
| vouch for (own devices) | convalidare | |
| raw (security key) | non formattata | |
| standby bucket | il gruppo di standby | Android's raw bucket names (rare, restricted, never) stay as they are. |
| Poor connection | Connessione scarsa | Apart from «Connessione debole». |
| mute / unmute (a chat's notifications) | Disattiva notifiche / Riattiva notifiche | |
| Chat / Room / Community info | Informazioni sulla chat / sulla stanza / sulla comunità | |
| Room / Community defaults | Impostazioni predefinite della stanza / della comunità | |
| {name} invited you (to …) | {name} ti invita (in …) | The present tense avoids «ti ha invitato/a». |
| Confirmed / Scanned / Approved (titles after a check) | Conferma completata / Scansione completata / Dispositivo approvato | |
| "You and {name} are…" | Recast so the verb is not plural «voi»: «Posizione in tempo reale condivisa da te e {name}». | |

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

## 2. Style rules

### 2.1 Register
- «tu» throughout, usually left implicit: «Tocca per riprovare», «Il tuo account è stato eliminato». Never «Lei», never «voi».
- "tap" → «tocca», "type" → «scrivi», "enter" → «inserisci», "choose/pick" → «scegli», "pull down" → «scorri verso il basso».

### 2.2 Buttons and body text

| Where | Form | Example |
|---|---|---|
| Buttons, menu items, tabs, tooltips, switches, row labels that act | Imperative (tu), as Android and iOS do | «Elimina account», «Salva», «Attiva altoparlante» |
| Body text, hints, the next step in an error | Imperative (tu) | «Tocca per riprovare.» |
| Titles that name something | Noun | «Impostazioni della stanza», «I tuoi dispositivi» |
| Titles that instruct | Imperative | «Salva il tuo codice di recupero» |
| Confirmation titles ("Delete X?") | Infinitive + «?» | «Eliminare il tuo account?» |
| Progress labels | Noun + «in corso…» or noun + «…» | «Creazione dell’account in corso…», «Caricamento…» |
| Success snack bars | Participle, English period kept or left out | «Password cambiata», «Segnalazione inviata» |

Buttons that answer a question stay statements: «Corrispondono», «Non corrispondono», «Sì, termina», «No, interrompi». First-person buttons stay first person: «Ho già un codice».

### 2.3 Case and punctuation
- Sentence case everywhere, as in the English. Weekday and month names are lowercase. Never all caps.
- No exclamation marks, no emoji. Keep «…» (one character) wherever the English has it.
- **Apostrophe:** the typographic ’ (U+2019) everywhere: «l’app», «un’altra». Never the straight '. Capital E with grave accent is «È», never «E’».
- Quotes: « » with no inner spaces, wherever the English has quotes. The one technical value keeps straight escaped quotes: `notificationsUnknownFormat` (`\"{type}\"`). Room, topic, device names and recovery words take « »: `«{name}»`.
- When body text names a screen, row, option or button, use its exact Italian label in « ». «Impostazioni» alone needs none.
- Keep the English «·» separators, colons and end punctuation exactly.

### 2.4 How Zuno speaks
- Zuno never speaks as «noi» or «io». Write «Zuno…» or recast impersonally.
- «Zuno», «Android», «iOS», «Google», «Apple», no article.
- Name no other apps beyond those the English names (ntfy, Google, Apple, CarPlay).

### 2.5 Names and gender (critical)
`{name}`, `{sender}`, `{target}`, `{first}`, `{second}`, `{people}` are display names of unknown gender, and the reader's gender is unknown too.
1. Never put an article before a name.
2. Subject names go first, bare, with verbs that take «avere», whose participle never agrees: «{target} ha lasciato», «{sender} ha invitato {target}», «{target} ha chiesto di entrare».
3. Never a participle with «essere» or an adjective that agrees with a person, the reader included: no «è entrato/a», «connesso/a», «invitato/a», «benvenuto/a». Recast with a noun or an «avere» verb: «Nuovo membro: {target}», «Accesso effettuato», «Hai bloccato {name}». Where a noun is needed, use «la persona» or «questa persona».
4. Short labels with a preposition are fine: «Con {name}», «Risposta a {name}», «Chiamata persa da {name}».
5. English "they" for one person → «questa persona» or drop the subject: "once they join" → «quando questa persona entra». No «@», «*» or «ə» endings.

### 2.6 Brand-voice moments

| Moment | Pattern |
|---|---|
| Error: what happened, then what to do | «Impossibile inviare il messaggio. Controlla la connessione e riprova.» |
| Fixed phrases | "Check your connection and try again." → «Controlla la connessione e riprova.» · "Pull down to try again." → «Scorri verso il basso per riprovare.» · "Too many attempts." → «Troppi tentativi.» · "Something went wrong." → «Si è verificato un problema.» |
| Irreversible | "Nobody can undo this." → always «Nessuno può annullare questa azione.» |
| Reassurance | Calm present tense, no alarm words. |
| Success | Flat participle, no «con successo». |

- Calm, plain, minimal. Italian runs about 20% longer than English: cut filler, never a limit, consequence or next step.
- No «Ci dispiace», «Purtroppo», superlatives or «sicuro al 100%».

### 2.7 Numbers, dates and units
- Numbers, dates and times stay inside their placeholders; never hard-code a format.
- "{date} at {time}" → «{date} alle {time}» · "Until {time}" → «Fino alle {time}» · "{days} days ago" → «{days} giorni fa» · "{page} of {total}" → «{page} di {total}».
- h, min, s, km, m, B, KB, MB stay as they are, with the space before them. Keep «%» where it is.
- Technical values stay exactly: `chat.example.org`, `https://`, `a–z, 0–9`, `@`, `ID`, `CarPlay`, `E2E`.

### 2.8 Ordinals
`securityOrdinal` precedes «parola» (feminine): `{n, select, 1{1ª} 2{2ª} 3{3ª} other{{n}ª}}`. `settingsRecoveryWordLabel` → «{position} parola». `settingsRecoveryConfirmBody` → «Scrivi la {first} e la {second} parola della copia salvata.»

### 2.9 Platform labels
- Name Android and iOS settings by that OS's Italian label. Both call Settings **Impostazioni**: "Settings → General → Language & Region" → «Impostazioni → Generali → Lingua e zona»; "Settings → Apps → Zuno → Language" → «Impostazioni → App → Zuno → Lingua».
- iOS notification settings: «Schermata di blocco», «Centro Notifiche», «Banner», «Badge», «Suoni», «Mostra anteprime», «Riepilogo programmato», «Avvisi critici», «Notifiche urgenti», «Annuncia notifiche».
- «iPhone» and «Android» as written. "your device" → «il tuo dispositivo», never «il tuo telefono».

---

## 3. ICU and placeholder rules (the build breaks otherwise)

- Copy every `{placeholder}` exactly. Never translate, rename, add or drop one; you may move it. A string made only of placeholders and symbols stays byte-identical (`{count}`, `{name} · {time}`, `{label}: {count}`, `{size} MB`, `CarPlay`, `UnifiedPush`).
- **Plurals:** keep structure and selector name. Use only `one` (exactly 1 in Italian) and `other`. Always write the number as `{count}`, never «uno» or «1».
  - Add a `one` case where the English has only `other` but Italian needs a singular: `matrixInvitePeopleInvited`, `matrixInviteWaitingForPeople`, `matrixSignupPasswordTooLong`, `securityPasswordTooShort`, `securityPasswordEmptyAdvice`, `settingsRecoveryCodeHint`, `settingsRecoveryRevealTitle`, `settingsRecoveryTooManyWords`, `roomInfoConfirmedCount`, and the `matrixRoomExitCommunityRooms*` family (both `count` and nested `orphaned`).
  - No `one` needed (same text for every number): `ageHours`, `ageMinutes`, `pushDelayHours`, `pushDelayMinutes`, `pushDelaySeconds`, `chatDeleteAllCount`, `chatSaveAll`, `chatShareAll`, `roomInfoMembersCount`, `notificationsMoreChatsAndRooms`.
  - Never add `zero`, `two`, `few`, `many` or `=n`; never use `#`. Every plural keeps `other`. Nested plurals keep their nesting.
- **Selects** (`notificationsFailureAutoSelected`, `pushSummaryPriority`, `pushSummaryStandbyBucket`, `securityOrdinal`): keep every case key; translate only the text; never drop `other`.
- **JSON:** apostrophes are literal (and typographic, §2.3). Escape `"` as `\"`. Put `\n` only where the English has it.
- **Native strings** (`x-native`): plain English stays plain; the three native plurals (`notificationsMoreChats`, `notificationsMoreRooms`, `notificationsMoreChatsAndRooms`) stay whole-message plurals. The five `x-ios-infoplist` keys have no placeholders and start with «Zuno…». Notification strings are the shortest text: keep them short.
- `languageNativeName` → «Italiano».

---

## 4. Worked examples

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
