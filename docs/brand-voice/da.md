# Brand voice: Danish (da)

Danish for `lib/l10n/app_da.arb`, written for Denmark. The rules all languages share are in `translating.md`; this guide holds only what is Danish.

**Binding, set by the product owner:**
- Address the reader as **du**, lowercase: «Skriv koden», «Dine beskeder», «inviterer dig».
- Chat = **chat**, room = **rum**, community = **fællesskab**. Never «gruppe», «kanal», «samtale» or «space» for any of them.
- **Zuno**, **Matrix**, **Google**, **Apple**, **Android** and **iOS** never take an ending; a possessive is recast with «i Zuno» or «fra Zuno». In compounds they take a hyphen («Google-konto», «Matrix-server»).
- `languageNativeName` → «Dansk».

---

## 1. Glossary

### 1.1 Brand-voice words

| English | da | Notes |
|---|---|---|
| chat (one-to-one) | chat · chatten · chats | "New chat" → «Ny chat». The "Chats" tab → «Chats». |
| room (group chat) | rum · rummet · rum | "New room" → «Nyt rum». |
| community | fællesskab · fællesskabet · fællesskaber | "New community" → «Nyt fællesskab». |
| "Group with {names}" | «Chat med {names}» | |
| Chat info / Room info / Community info | Chatinfo / Ruminfo / Info om fællesskabet | |
| device | enhed · enheden · enheder | Never «telefon» or «mobil». |
| recovery code | gendannelseskode | Never «nøgle» or «adgangskode». |
| recovery | gendannelse | "Set up recovery" → «Konfigurer gendannelse». |
| sign in | Log ind · login | "New sign-in" → «Nyt login». A signed-in device → «en enhed, der er logget ind». |
| sign out | Log ud | "Sign out everywhere else" → «Log ud alle andre steder». |
| sign up, sign-up code | Opret konto · oprettelse · oprettelseskode | Push registration is «push-registrering». |
| server, homeserver | server | |

### 1.2 People

| English | da | Notes |
|---|---|---|
| person, people | person · personer | «personen», «denne person». |
| user / member | person / medlem | "Unknown user" → «Ukendt person». Never «bruger» about a person; «brugernavn» (the field) is fine. "Search members" → «Søg efter medlemmer». |
| You (own name on tiles and the map) | Dig | |
| Someone / Anyone / Nobody / Everyone | Nogen / Alle / Ingen / Alle | "Anyone can join" → «Alle kan deltage». |
| guest, stranger | gæst · en fremmed | |

### 1.3 Messaging

| English | da | Notes |
|---|---|---|
| message | besked · beskeden · beskeder | Composer placeholder "Message" → «Besked». |
| send | Send · afsendelse | "Not sent" → «Ikke sendt». "Sending…" → «Sender…». |
| reply | Svar | "Replying to {name}" → «Svarer {name}». |
| reaction, react | reaktion · reager | |
| edit, edited | Rediger · redigeret | "(edited)" → «(redigeret)». |
| delete | Slet · sletning | "Message deleted" → «Besked slettet». |
| remove (an item or a person) | Fjern | "Remove from room" → «Fjern fra rummet». Never «slet» for a person. |
| hidden (not shown) | skjult · vises ikke | |
| seen, seen by | Set · Set af: {people} | "Not seen yet" → «Ikke set endnu». |
| typing | skriver… | "{name} is typing…" → «{name} skriver…». "Several people are typing…" → «Flere personer skriver…». |
| mention | nævn · omtale | "Mentions only" → «Kun omtaler». |
| attachment, voice message | vedhæftet fil · talebesked | |
| photo / video / file | billede / video / fil | |
| media, item | medier · element | The "Media" heading → «Medier». "Delete 3 items?" → «Slet 3 elementer?». |
| caption, gallery | billedtekst · galleri | iOS Photos app → «Fotos». |
| history | historik | |
| record, upload, download, reload | optag · upload · download · genindlæs | "Uploading…" → «Uploader…». "Downloading…" → «Downloader…». «Indlæser…» is Loading only. |
| emoji, verification emoji | emoji · billeder | |
| link | link | |

### 1.4 Calls

| English | da | Notes |
|---|---|---|
| call, voice call, video call | opkald · taleopkald · videoopkald | Button "Call" → «Ring op». |
| ring, ringtone, full screen | ringe · ringetone · fuld skærm | |
| incoming / missed / ongoing call | indgående / ubesvaret / igangværende opkald | "Missed call from {name}" → «Ubesvaret opkald fra {name}». |
| Accept / Decline | Besvar / Afvis (calls) · Accepter / Afvis (invites, requests) | |
| hang up, End call | Læg på | Both. |
| join (a call) | Deltag | |
| speaker, mute, unmute | højttaler · Slå lyd fra · Slå lyd til | "Muted" → «Lyd fra». "{name} is muted" → «{name} har slået lyden fra». |
| mute someone, remove from the call | Slå lyd fra · Fjern fra opkaldet | Muting another person is «slå lyden fra for»: "{name} muted you" → «{name} har slået lyden fra for dig». "Rejoin" → «deltage igen». A person's "Show options" → «Vis valgmuligheder». |
| camera, microphone | kamera · mikrofon | |
| connection, connecting, reconnecting | forbindelse · Opretter forbindelse… · Genopretter forbindelse… | "Weak connection" → «Svag forbindelse». "Poor connection" → «Dårlig forbindelseskvalitet». "Calling…" → «Ringer op…». |
| picture-in-picture, minimize | billede-i-billede · Minimer | |

### 1.5 Security and encryption

| English | da | Notes |
|---|---|---|
| encryption, encrypted, decrypt | kryptering · krypteret · dekrypter | |
| end-to-end encrypted | end-to-end-krypteret | |
| confirm (a person) | Bekræft · bekræftelse | "Confirmed people only" → «Kun bekræftede personer». |
| approve (own device) | Godkend · godkendelse | |
| verify, verification | verificer · verificering | |
| security details | sikkerhedsoplysninger | |
| key, room keys | nøgle · rumnøgler | |
| backup, key backup, restore | sikkerhedskopi · sikkerhedskopi af nøgler · gendan | |
| security key, security phrase, recovery key | sikkerhedsnøgle · sikkerhedssætning · gendannelsesnøgle | |
| cross-signing, secret storage | krydssignering · hemmeligt lager | |
| session | session | |
| unlock, trust | lås op · stole på | |
| scan, QR code, code | Scan · QR-kode · kode | "Scan code" → «Scan koden». |
| screenshot, screen recording, screen sharing | skærmbillede · skærmoptagelse · skærmdeling | |
| block | Bloker / Fjern blokering | |
| rooted device, compromised device | rootet enhed · kompromitteret enhed | |
| clipboard, password manager | udklipsholder · adgangskodeadministrator | |
| incognito keyboard | inkognitotastatur | |
| Cryptography | kryptografi | Encryption stays «kryptering». |
| raw (security key), vouch for | rå · godkend | |
| generate, export, import, in person | generer · eksporter · importer · ansigt til ansigt | |

### 1.6 Account, server and membership

| English | da | Notes |
|---|---|---|
| account, password | konto · adgangskode | "Wrong password." → «Forkert adgangskode.» "Confirm password" (the repeat field) → «Gentag adgangskode». |
| username, display name | brugernavn · visningsnavn | |
| profile, profile photo | profil · profilbillede | |
| email address | mailadresse | |
| invite | Inviter · invitation | The "Invited" badge → «Inviteret». |
| withdraw (an invitation) | trække invitationen tilbage | "{sender} withdrew your invitation" → «{sender} trak din invitation tilbage». |
| join (a room or community) | Deltag · deltage | "{people} joined" → «{people} deltager nu». "Joined and left" → «deltog og gik igen». |
| request, ask to join | anmodning · Anmod om at deltage | Short "Ask" button → «Anmod». "Requested" → «Anmodet». "Let in" → «Giv adgang». "Withdraw" → «Træk tilbage». |
| leave | Forlad · forlade | "{people} left" → «{people} er gået». |
| ban | Udeluk / Ophæv udelukkelse · udelukkelse | "Banned" heading → «Udelukkede». "{sender} unbanned {people}" → «{sender} ophævede udelukkelsen af {people}». Never «bloker». |
| report | Rapporter · rapport | Reasons: «Chikane», «Ulovligt indhold», «Spam», «Anden årsag». |
| public / private | offentlig / privat | Agree with the noun («et offentligt rum», «et privat fællesskab»); a label serving both is «Offentlig adgang» / «Privat adgang» / «Adgang efter anmodning» / «Adgang for fællesskabet». "Make public" → «Gør offentlig». |
| topic, description, address, ID | emne · beskrivelse · adresse · ID | Room alias → «rumadresse». |
| hostname | servernavn | |
| defaults, default role | standardindstillinger · standardrolle | |

### 1.7 Roles and permissions

| English | da | Notes |
|---|---|---|
| admin, moderator, owner | Administrator · Moderator · Ejer | |
| role, member, read-only, view only | rolle · Medlem · Kun læsning · Kun visning | |
| give a role ("made {people} an admin", "you are now an admin") | give {people} rollen “…” · Du har nu rollen “…” | With the role's label, the same for every role, since «Kun læsning» is no person noun. |
| permission (room or OS), access | tilladelse · adgang | "Roles & permissions" → «Roller og tilladelser». Permission names are infinitives: "Remove people" → «Fjerne personer», "Change name" → «Ændre navn». |

### 1.8 Notifications and push

| English | da | Notes |
|---|---|---|
| notification, test notification | notifikation · testnotifikation | |
| alert, security alerts | advarsel · sikkerhedsadvarsler | iOS's Alerts → «Advarsler»; call alerts → «opkaldsvarsler». |
| push, push target, push key | push · push-mål · push-nøgle | "push notifications" → «push-notifikationer». |
| registration (push) | registrering · registrer | |
| delivery, background sync | levering · baggrundssynkronisering | "Delivery method" → «Leveringsmetode». |
| battery use: Unrestricted / Optimized / Restricted | Batteriforbrug: Ubegrænset / Optimeret / Begrænset | Android's labels. |
| Data Saver, Autostart | Datasparefunktion · Autostart | |
| distributor | distributør | |
| Google services / Google Play services | Google-tjenester / Google Play-tjenester | |
| Apple push | Apple-push | |
| gateway, bridge, token | gateway · bro · token | |
| notification extension, crash | notifikationsudvidelse · nedbrud | "Crashed" → «Gik ned». |
| diagnostics | diagnosticering | |
| notification category, notification shade | notifikationskategori · notifikationspanelet | |
| lock screen | låseskærm | |
| quiet, sound, vibration | lydløs · lyd · vibration | "Message tone" → «Beskedlyd». |
| standby bucket | standbygruppe | |

### 1.9 Location

| English | da | Notes |
|---|---|---|
| location, live location | placering · liveplacering | |
| share, start / stop sharing | Del · Start / Stop deling | Also for sharing files. |
| approximate, maps app | omtrentlig · kortapp | |

### 1.10 Settings, storage and data

| English | da | Notes |
|---|---|---|
| Settings | Indstillinger | Zuno's, Android's and iOS's. |
| storage, data, cache | lagerplads · data · cache | "Clear cache" → «Ryd cache». "Data & storage" → «Data og lagerplads». |
| theme: Dark / Light / Follow system | Mørkt / Lyst / Følg systemet | |
| Appearance / About / Advanced, version, build | Udseende / Om / Avanceret · version · build | |
| feedback, crash reports | feedback · nedbrudsrapporter | "Send feedback" → «Send feedback». |
| donate, privacy, Privacy policy, Terms | Donér · privatliv · Privatlivspolitik · Vilkår | |
| browser, underscore | browser · understregning | |
| app, home screen, shortcut, launcher | app · hjemmeskærm · genvej · launcher | A chat app is «beskedapp». |
| recent apps, app switcher | seneste apps · appskifter | |
| Open source licenses, Source code | Open source-licenser · Kildekode | |

### 1.11 Settled phrases

| English | da | Notes |
|---|---|---|
| Asking to join (admin heading) | Anmodninger om at deltage | "Asking to join {name}" → «Anmodninger om at deltage i “{name}”». |
| Ask to join (subtitle under "{name} and N others") / Asks to join | Anmoder om at deltage / Anmoder om at deltage | Both mean the people named are asking. The button stays «Anmod om at deltage». |
| Let them ask (setting) | Tillad anmodninger | |
| Joined (label on a public room or community) | Medlem | |
| N other(s) | {count} anden · {count} andre | one · other. |
| asleep (device) / suspended (app) | i dvale / sat på pause | |
| Call rang / ringing | Ringede / Ringer | |
| Hidden message | skjult besked | Never «hemmelig». |
| Secure backup (screen) | “Gendannelse” | |
| Welcome to Zuno | Velkommen til Zuno | |
| With {name} / In {name} (room) / {name}'s devices | Med {name} / I rummet “{name}” / Enheder: {name} | |
| {name} is confirmed | {name} er bekræftet | |
| character(s), check mark | tegn · flueben | |
| reinstall, sign-in code, the verification check | geninstallation · loginkode · kontrollen | |
| "{type} event" | «Hændelse: {type}» | |

### 1.12 UI actions

| English | da |
|---|---|
| Cancel / Save / Saved | Annuller / Gem / Gemt |
| Delete / Remove | Slet / Fjern |
| Copy / Copied / Share | Kopier / Kopieret / Del |
| Send / Continue / Continue anyway | Send / Fortsæt / Fortsæt alligevel |
| Done / Retry / Try again | Færdig / Prøv igen / Prøv igen |
| Close / Dismiss / Open / Open settings | Luk / Afvis / Åbn / Åbn indstillinger |
| Turn on / Turn off · On / Off | Slå til / Slå fra · Til / Fra |
| Allow / Not now / Skip | Tillad / Ikke nu / Spring over |
| Confirm / Approve | Bekræft / Godkend |
| Create / Start / Get started | Opret / Start / Kom i gang |
| Edit / Change / Review | Rediger / Skift / Gennemse |
| Back / Stop / Play | Tilbage / Stop / Afspil |
| Read more / Show less | Vis mere / Vis mindre |
| Mark as read / Unread | Markér som læst / Ulæst |
| Refresh / Search / Start over | Opdater / Søg / Start forfra |

### 1.13 Status words

| English | da |
|---|---|
| Loading… / Sending… / Waiting… | Indlæser… / Sender… / Venter… |
| Checking… / Searching… | Tjekker… / Søger… |
| Failed | Mislykkedes |
| Not set / Unknown / None / Never | Ikke angivet / Ukendt / Ingen / Aldrig |
| Not available / Yes / No / Status | Ikke tilgængelig / Ja / Nej / Status |
| Just now / Today / Yesterday / Coming soon | Lige nu / I dag / I går / Kommer snart |

---

## 2. Danish rules

### 2.1 Register
- «du» throughout, lowercase: «du», «dig», «din», «dit», «dine». Never the formal «De».
- Drop the possessive where Danish does: «Tjek forbindelsen» is fine, «din» only where it adds meaning.
- "tap" → «tryk på», "type" and "enter" → «skriv» or «angiv», "choose/pick" → «vælg», "pull down" → «træk ned», "swipe" → «stryg».

### 2.2 Forms

| Where | Form | Example |
|---|---|---|
| Buttons, menu items, tooltips, actions in rows | Imperative | «Slet konto», «Gem», «Slå højttaler til» |
| Tabs, switches and labels that name a thing | Noun | «Chats», «Notifikationer», «Højttaler» |
| Body text, hints, the next step in an error | Imperative | «Tryk for at prøve igen.» |
| Titles that name something | Noun | «Rumindstillinger», «Dine enheder» |
| Titles that instruct | Imperative | «Gem din gendannelseskode» |
| Confirmation titles ("Delete X?") | Imperative + «?» | «Slet kontoen?» |
| Progress labels | Present tense + «…» | «Opretter konto…», «Sender…» |
| Success snack bars | Noun + participle | «Adgangskode ændret», «Rapport sendt» |

Statement and first-person buttons: «De matcher», «De matcher ikke», «Ja, afslut», «Nej, stop», «Jeg har allerede en kode».

### 2.3 Typography
- Quotes: “…” (U+201C, U+201D), and ‘…’ inside them: `“{name}”`.
- No space before «?», «!», «:» or «;».
- Apostrophe: typographic ’ only.
- Compounds are written as one word; after an acronym, a brand or an English word, they take a hyphen: «QR-kode», «Google-konto», «push-notifikation».
- Comma before «og» between two clauses that each have a verb: «Tjek din forbindelse, og prøv igen.»

### 2.4 Names
Danish marks no gender on verbs or adjectives, so «{name} er bekræftet» is safe. Two things are not safe: the pronouns «han/hun», and an ending on a name («Annas enheder», where a name ending in s would need «Jens’»).

1. Never attach an ending to a placeholder. A possessive is recast: «Enheder: {name}», «{name} har en ny enhed».
2. Refer back with «personen» or «denne person», never «han» or «hun».
3. English singular "they" → «personen», or drop it.

### 2.5 Fixed phrases
- Error pattern: «Beskeden blev ikke sendt. Tjek din forbindelse, og prøv igen.»
- "Check your connection and try again." → «Tjek din forbindelse, og prøv igen.»
- "Pull down to try again." → «Træk ned for at prøve igen.»
- "Could not X." → «Kunne ikke X.» as a short label; with a subject, «X kunne ikke …»: «Rummet kunne ikke oprettes.»
- "Too many attempts." → «For mange forsøg.» · "Something went wrong." → «Noget gik galt.»
- "Nobody can undo this." → always «Ingen kan fortryde dette.»
- Never «desværre», «beklager», «undskyld», «med succes» or «100 % sikker».

### 2.6 Numbers, dates and units
- "{date} at {time}" → «{date} kl. {time}» · "Until {time}" → «Indtil {time}» · "{days} days ago" → «for {days} dage siden» (one: «for {days} dag siden») · "{page} of {total}" → «{page} af {total}».
- h → «t»: «for {hours} t siden». min and s stay.
- Danish plurals have two cases: `one` is exactly 1, and 0 is `other`: «0 medlemmer».

### 2.7 Ordinals
Danish writes an ordinal as the number and a full stop. `securityOrdinal`: `{n, select, 1{1.} 2{2.} 3{3.} other{{n}.}}`. `settingsRecoveryWordLabel` → «{position} ord». `settingsRecoveryConfirmBody` → «Skriv det {first} og {second} ord fra din gemte kopi.»

### 2.8 Platform labels
- Android: "Settings → Apps → Zuno → Language" → «Indstillinger → Apps → Zuno → Sprog».
- iOS: "Settings → General → Language & Region" → «Indstillinger → Generelt → Sprog og område»; «Lokalitetstjenester», «Anonymitet og sikkerhed», the Photos app «Fotos», and the notification settings «Advarsler», «Kendetegn», «Bannerstil», «Kritiske advarsler», «Direkte beskeder», «Låseskærm», «Notifikationscenter», «Planlagt oversigt», «Vis eksempler», «Lyde», «Tidsfølsomme notifikationer», «Oplæs notifikationer».

---

## 3. Worked examples

| Key | English | da |
|---|---|---|
| `settingsDeleteAccountWarningTitle` | Delete your account? | Slet din konto? |
| `feedbackNotSent` | Feedback not sent. Check your connection and try again. | Feedback blev ikke sendt. Tjek din forbindelse, og prøv igen. |
| `chatNotSentRetry` | Not sent · Tap to retry | Ikke sendt · Tryk for at prøve igen |
| `callsFailureOnAnotherDevice` | You are in this call on another device. Hang up there to join here. | Du er med i opkaldet på en anden enhed. Læg på der for at deltage her. |
| `settingsAccountPasswordChanged` | Password changed | Adgangskode ændret |
| `blockingTitle` | Block {name}? | Bloker {name}? |
| `matrixStateNameChanged` | `{sender} changed the room name to \"{name}\"` | `{sender} ændrede rummets navn til “{name}”` |
| `matrixStateInvited` | `{count, plural, other{{sender} invited {people}}}` | `{count, plural, other{{sender} inviterede {people}}}` |
| `roomInfoIsConfirmed` | {name} is confirmed | {name} er bekræftet |
| `chatDeleteTitle` | `{count, plural, one{Delete message?} other{Delete {count} items?}}` | `{count, plural, one{Slet beskeden?} other{Slet {count} elementer?}}` |
| `matrixInvitePeopleInvited` | `{count, plural, other{{count} people invited}}` | `{count, plural, one{{count} person inviteret} other{{count} personer inviteret}}` |
| `permissionsPhotoLibraryAddUsage` | Zuno saves photos and videos to your library only when you tap Save. | Zuno gemmer kun billeder og videoer i dit bibliotek, når du trykker på “Gem”. |
