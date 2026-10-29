# Brand voice: Dutch (nl)

Dutch for `lib/l10n/app_nl.arb`, written for the Netherlands and Flanders alike. The rules all languages share are in `translating.md`; this guide holds only what is Dutch.

**Binding, set by the product owner:**
- Address the reader as **je**, lowercase: «Typ de code», «Je berichten», «nodigt je uit». «jij/jou» only for stress.
- Chat = **chat**, room = **kamer**, community = **community**. Never «groep», «kanaal», «gesprek», «ruimte» or «gemeenschap» for any of them.
- **Zuno**, **Matrix**, **Google**, **Apple**, **Android** and **iOS** never take a genitive: «de instellingen van Zuno». In compounds they take a hyphen: «Google-account», «Matrix-server».
- `languageNativeName` → «Nederlands».

---

## 1. Glossary

### 1.1 Brand-voice words

| English | nl | Notes |
|---|---|---|
| chat (one-to-one) | chat · de chat · chats | "New chat" → «Nieuwe chat». The "Chats" tab → «Chats». |
| room (group chat) | kamer · de kamer · kamers | "New room" → «Nieuwe kamer». |
| community | community · de community · communities | "New community" → «Nieuwe community». |
| "Group with {names}" | «Chat met {names}» | |
| Chat info / Room info / Community info | Chatinfo / Kamerinfo / Communityinfo | |
| device | apparaat · het apparaat · apparaten | Never «telefoon» or «mobiel». |
| recovery code | herstelcode | Never «sleutel» or «wachtwoord». |
| recovery | herstel | "Set up recovery" → «Herstel instellen». |
| sign in | Inloggen · inlog | "New sign-in" → «Nieuwe inlog». A signed-in device → «ingelogd apparaat». |
| sign out | Uitloggen | "Sign out everywhere else" → «Overal anders uitloggen». |
| sign up, sign-up code | Account maken · registratie · registratiecode | Push registration is «pushregistratie». |
| server, homeserver | server | |

### 1.2 People

| English | nl | Notes |
|---|---|---|
| person, people | persoon · personen · mensen | «deze persoon». |
| user / member | persoon / lid · leden | "Unknown user" → «Onbekende persoon». Never «gebruiker» about a person; «gebruikersnaam» (the field) is fine. "Search members" → «Leden zoeken». |
| You (own name on tiles and the map) | Jij | |
| Someone / Anyone / Nobody / Everyone | Iemand / Iedereen / Niemand / Iedereen | "Anyone can join" → «Iedereen kan lid worden». |
| guest, stranger | gast · een vreemde | |

### 1.3 Messaging

| English | nl | Notes |
|---|---|---|
| message | bericht · het bericht · berichten | Composer placeholder "Message" → «Bericht». |
| send | Versturen | "Not sent" → «Niet verstuurd». "Sending…" → «Versturen…». |
| reply | Beantwoorden | "Replying to {name}" → «Antwoord aan {name}». |
| reaction, react | reactie · reageren | |
| edit, edited | Bewerken · bewerkt | "(edited)" → «(bewerkt)». |
| delete | Verwijderen | "Message deleted" → «Bericht verwijderd». |
| remove (an item) | Weghalen | "Remove photo" → «Foto weghalen». Keeps it apart from delete. |
| remove (a person) | Verwijderen uit … | "Remove from room" → «Verwijderen uit kamer»; the place always follows in the dialog. |
| hidden (not shown) | verborgen · wordt niet getoond | |
| seen, seen by | Gezien · Gezien door: {people} | "Not seen yet" → «Nog niet gezien». |
| typing | typt… | "{name} is typing…" → «{name} typt…». "Several people are typing…" → «Meerdere mensen typen…». |
| mention | vermelden · vermelding | "Mentions only" → «Alleen vermeldingen». |
| attachment, voice message | bijlage · spraakbericht | |
| photo / video / file | foto · foto’s / video · video’s / bestand | |
| media, item | media · item | The "Media" heading → «Media». "Delete 3 items?" → «3 items verwijderen?». |
| caption, gallery | onderschrift · galerij | iOS Photos app → «Foto’s». |
| history | geschiedenis | |
| record, upload, download, reload | opnemen · uploaden · downloaden · opnieuw laden | "Uploading…" → «Uploaden…». "Downloading…" → «Downloaden…». «Laden…» is Loading only. |
| emoji, verification emoji | emoji · afbeeldingen | |
| link | link | |

### 1.4 Calls

| English | nl | Notes |
|---|---|---|
| call, voice call, video call | oproep · spraakoproep · video-oproep | Button "Call" → «Bellen». Never «gesprek», which reads as a chat. |
| ring, ringtone, full screen | overgaan · beltoon · volledig scherm | |
| incoming / missed / ongoing call | inkomende / gemiste / lopende oproep | "Missed call from {name}" → «Gemiste oproep van {name}». |
| Accept / Decline | Opnemen / Weigeren (calls) · Accepteren / Weigeren (invites, requests) | |
| hang up, End call | Ophangen | Both. |
| join (a call) | Deelnemen | |
| speaker, mute, unmute | luidspreker · Dempen · Dempen opheffen | "Muted" → «Gedempt». "{name} is muted" → «{name} heeft het geluid gedempt». |
| mute someone, remove from the call | Dempen · Verwijderen uit oproep | Another person is muted directly: "{name} muted you" → «{name} heeft je gedempt». A failure is «Kon {name} niet …», since «{name} is niet gedempt» reads as a state. "Rejoin" → «opnieuw deelnemen». A person's "Show options" → «Opties tonen». |
| camera, microphone | camera · microfoon | |
| connection, connecting, reconnecting | verbinding · Verbinden… · Opnieuw verbinden… | "Weak connection" → «Zwakke verbinding». "Poor connection" → «Slechte verbindingskwaliteit». "Calling…" → «Bellen…». |
| picture-in-picture, minimize | beeld-in-beeld · Minimaliseren | |

### 1.5 Security and encryption

| English | nl | Notes |
|---|---|---|
| encryption, encrypted, decrypt | versleuteling · versleuteld · ontsleutelen | |
| end-to-end encrypted | end-to-end versleuteld | |
| confirm (a person) | Bevestigen · bevestiging | "Confirmed people only" → «Alleen bevestigde personen». |
| approve (own device) | Goedkeuren · goedkeuring | |
| verify, verification | verifiëren · verificatie | |
| security details | beveiligingsgegevens | |
| key, room keys | sleutel · kamersleutels | |
| backup, key backup, restore | back-up · sleutelback-up · terugzetten | «herstel» is recovery only. |
| security key, security phrase, recovery key | beveiligingssleutel · beveiligingszin · herstelsleutel | |
| cross-signing, secret storage | kruislings ondertekenen · geheime opslag | |
| session | sessie | |
| unlock, trust | ontgrendelen · vertrouwen | |
| scan, QR code, code | Scannen · QR-code · code | "Scan code" → «Code scannen». |
| screenshot, screen recording, screen sharing | screenshot · schermopname · scherm delen | |
| block | Blokkeren / Deblokkeren | |
| rooted device, compromised device | geroot apparaat · gecompromitteerd apparaat | |
| clipboard, password manager | klembord · wachtwoordbeheerder | |
| incognito keyboard | incognitotoetsenbord | |
| Cryptography | cryptografie | Encryption stays «versleuteling». |
| raw (security key), vouch for | onbewerkt · goedkeuren | |
| generate, export, import, in person | genereren · exporteren · importeren · in het echt | |

### 1.6 Account, server and membership

| English | nl | Notes |
|---|---|---|
| account, password | account · wachtwoord | "Wrong password." → «Onjuist wachtwoord.» "Confirm password" (the repeat field) → «Wachtwoord herhalen». |
| username, display name | gebruikersnaam · weergavenaam | |
| profile, profile photo | profiel · profielfoto | |
| email address | e-mailadres | |
| invite | Uitnodigen · uitnodiging | The "Invited" badge → «Uitgenodigd». |
| withdraw (an invitation) | uitnodiging intrekken | "{sender} withdrew your invitation" → «{sender} heeft je uitnodiging ingetrokken». |
| join (a room or community) | Lid worden | "{people} joined" → «{people} is lid geworden», several «zijn lid geworden». "Joined and left" → «is lid geworden en weer vertrokken». |
| request, ask to join | verzoek · Vragen om lid te worden | Short "Ask" button → «Vragen». "Requested" → «Aangevraagd». "Let in" → «Toelaten». "Withdraw" → «Intrekken». |
| leave | Verlaten | "{people} left" → «{people} is vertrokken». |
| ban | Verbannen / Verbanning opheffen · verbanning | "Banned" heading → «Verbannen». "{sender} unbanned {people}" → «{sender} heeft de verbanning van {people} opgeheven». Never «blokkeren». |
| report | Rapporteren · rapport | «melding» is a notification. Reasons: «Intimidatie», «Illegale inhoud», «Spam», «Andere reden». |
| the people who run your server | de mensen achter je server | Who receives reports, never Zuno. Never «beheerders», which are room admins. "They" → «zij». |
| public / private | openbaar / privé | A label serving both rooms and communities is «Openbare toegang» / «Privétoegang» / «Toegang op verzoek» / «Toegang voor de community». "Make public" → «Openbaar maken». |
| topic, description, address, ID | onderwerp · beschrijving · adres · ID | Room alias → «kameradres». |
| hostname | servernaam | |
| defaults, default role | standaardinstellingen · standaardrol | |

### 1.7 Roles and permissions

| English | nl | Notes |
|---|---|---|
| admin, moderator, owner | Beheerder · Moderator · Eigenaar | |
| role, member, read-only, view only | rol · Lid · Alleen lezen · Alleen bekijken | |
| give a role ("made {people} an admin", "you are now an admin") | {people} de rol ‘…’ geven · Je hebt nu de rol ‘…’ | With the role's label; never «{people} beheerder maken», as «beheerder» has a feminine form. |
| permission (room), permission (OS), access | recht · toestemming · toegang | "Roles & permissions" → «Rollen en rechten». Permission names are infinitive phrases: "Remove people" → «Personen verwijderen», "Change name" → «Naam wijzigen». |

### 1.8 Notifications and push

| English | nl | Notes |
|---|---|---|
| notification, test notification | melding · testmelding | |
| alert, security alerts | melding · beveiligingsmeldingen | Call and iOS alerts are «meldingen» too («Oproepmeldingen op volledig scherm»). |
| push, push target, push key | push · pushdoel · pushsleutel | "push notifications" → «pushmeldingen». |
| registration (push) | registratie · registreren | |
| delivery, background sync | bezorging · achtergrondsynchronisatie | "Delivery method" → «Bezorgmethode». |
| battery use: Unrestricted / Optimized / Restricted | Batterijgebruik: Onbeperkt / Geoptimaliseerd / Beperkt | Android's labels. |
| Data Saver, Autostart | Databesparing · Autostart | |
| distributor | distributeur | |
| Google services / Google Play services | Google-services / Google Play-services | |
| Apple push | Apple-push | |
| gateway, bridge, token | gateway · brug · token | |
| notification extension, crash | meldingsextensie · crash | "Crashed" → «Gecrasht». |
| diagnostics | diagnostiek | |
| notification category, notification shade | meldingscategorie · het meldingenpaneel | |
| lock screen | vergrendelscherm | |
| quiet, sound, vibration | stil · geluid · trillen | "Message tone" → «Berichttoon». "Chat tones" → «Chattonen». |
| standby bucket | stand-bycategorie | |

### 1.9 Location

| English | nl | Notes |
|---|---|---|
| location, live location | locatie · livelocatie | |
| share, start / stop sharing | Delen · Delen starten / Delen stoppen | Also for sharing files. |
| approximate, maps app | geschat · kaarten-app | |

### 1.10 Settings, storage and data

| English | nl | Notes |
|---|---|---|
| Settings | Instellingen | Zuno's, Android's and iOS's. |
| storage, data, cache | opslag · data · cache | "Clear cache" → «Cache wissen». "Data & storage" → «Data en opslag». |
| theme: Dark / Light / Follow system | Donker / Licht / Systeem volgen | |
| Appearance / About / Advanced, version, build | Weergave / Over / Geavanceerd · versie · build | |
| feedback, crash reports | feedback · crashrapporten | "Send feedback" → «Feedback sturen». |
| donate, privacy, Privacy policy, Terms | Doneren · privacy · Privacybeleid · Voorwaarden | |
| building Zuno (what donations pay for) | de ontwikkeling van Zuno | |
| free and open source | gratis en open source | "Zuno is free and open source." → «Zuno is gratis en open source.» |
| browser, underscore | browser · liggend streepje | |
| app, home screen, shortcut, launcher | app · startscherm · snelkoppeling · launcher | A chat app is «berichtenapp». |
| recent apps, app switcher | recente apps · appkiezer | |
| Open source licenses, Source code | Opensourcelicenties · Broncode | |

### 1.11 Settled phrases

| English | nl | Notes |
|---|---|---|
| Asking to join (admin heading) | Verzoeken om lid te worden | "Asking to join {name}" → «Verzoeken voor ‘{name}’». |
| Ask to join (subtitle under "{name} and N others") / Asks to join | Vragen om lid te worden / Vraagt om lid te worden | Both mean the people named are asking. The button stays «Vragen om lid te worden». |
| Let them ask (setting) | Verzoeken toestaan | |
| Joined (label on a public room or community) | Lid | |
| N other(s) | {count} ander · {count} anderen | one · other. |
| asleep (device) / suspended (app) | in slaapstand / onderbroken | |
| Call rang / ringing | Ging over / Gaat over | |
| Hidden message | verborgen bericht | Never «geheim». |
| Secure backup (screen) | ‘Herstel’ | |
| Welcome to Zuno | Welkom bij Zuno | |
| With {name} / In {name} (room) / {name}'s devices | Met {name} / In de kamer ‘{name}’ / Apparaten van {name} | |
| {name} is confirmed | {name} is bevestigd | |
| character(s), check mark | teken · tekens · vinkje | |
| reinstall, sign-in code, the verification check | herinstallatie · inlogcode · de controle | |
| "{type} event", "your friend" | «Gebeurtenis {type}» · «je contactpersoon» | «vriend» marks gender. |

### 1.12 UI actions

| English | nl |
|---|---|
| Cancel / Save / Saved | Annuleren / Opslaan / Opgeslagen |
| Delete / Remove (item) | Verwijderen / Weghalen |
| Copy / Copied / Share | Kopiëren / Gekopieerd / Delen |
| Send / Continue / Continue anyway | Versturen / Doorgaan / Toch doorgaan |
| Done / Retry / Try again | Klaar / Opnieuw / Opnieuw proberen |
| Close / Dismiss / Open / Open settings | Sluiten / Negeren / Openen / Instellingen openen |
| Turn on / Turn off · On / Off | Aanzetten / Uitzetten · Aan / Uit |
| Allow / Not now / Skip | Toestaan / Niet nu / Overslaan |
| Confirm / Approve | Bevestigen / Goedkeuren |
| Create / Start / Get started | Maken / Starten / Aan de slag |
| Edit / Change / Review | Bewerken / Wijzigen / Controleren |
| Back / Stop / Play | Terug / Stoppen / Afspelen |
| Read more / Show less | Meer tonen / Minder tonen |
| Mark as read / Unread | Markeren als gelezen / Ongelezen |
| Refresh / Search / Start over | Vernieuwen / Zoeken / Opnieuw beginnen |

### 1.13 Status words

| English | nl |
|---|---|
| Loading… / Sending… / Waiting… | Laden… / Versturen… / Wachten… |
| Checking… / Searching… | Controleren… / Zoeken… |
| Failed | Mislukt |
| Not set / Unknown / None / Never | Niet ingesteld / Onbekend / Geen / Nooit |
| Not available / Yes / No / Status | Niet beschikbaar / Ja / Nee / Status |
| Just now / Today / Yesterday / Coming soon | Zojuist / Vandaag / Gisteren / Binnenkort |

---

## 2. Dutch rules

### 2.1 Register
- «je» throughout, lowercase: «je», «jouw» only for stress. Never «u» or «uw».
- Drop the possessive where Dutch does: «Controleer je verbinding» is natural; never stack «je» where «de» reads better.
- "tap" → «tik op», "type" and "enter" → «typ» or «voer in», "choose/pick" → «kies», "pull down" → «trek omlaag», "swipe" → «veeg».

### 2.2 Forms

| Where | Form | Example |
|---|---|---|
| Buttons, menu items, tooltips, actions in rows | Infinitive, object first | «Account verwijderen», «Opslaan», «Luidspreker aanzetten» |
| Tabs, switches and labels that name a thing | Noun | «Chats», «Meldingen», «Luidspreker» |
| Body text, hints, the next step in an error | Imperative (je) | «Tik om het opnieuw te proberen.» |
| Titles that name something | Noun | «Kamerinstellingen», «Je apparaten» |
| Titles that instruct | Imperative | «Bewaar je herstelcode» |
| Confirmation titles ("Delete X?") | Infinitive + «?» | «Account verwijderen?» |
| Progress labels | Infinitive + «…» | «Account maken…», «Versturen…» |
| Success snack bars | Noun + participle | «Wachtwoord gewijzigd», «Rapport verstuurd» |

Statement and first-person buttons: «Ze komen overeen», «Ze komen niet overeen», «Ja, afronden», «Nee, stoppen», «Ik heb al een code».

### 2.3 Typography
- Quotes: ‘…’ (U+2018, U+2019), and “…” inside them: `‘{name}’`.
- No space before «?», «!», «:» or «;».
- Apostrophe: typographic ’, also in plurals of words ending in a vowel: «foto’s», «video’s».
- Compounds are written as one word; after an acronym, a brand or where two vowels collide, they take a hyphen: «QR-code», «Google-account», «video-oproep».
- Keep the diaeresis: «kopiëren», «verifiëren».

### 2.4 Names
Dutch marks no gender on verbs or adjectives, and names never change form, so «{name} is bevestigd» and «van {name}» are safe. Two things are not safe: the pronouns «hij/zij», and a genitive ending on a name («Anna’s apparaten»).

1. Never attach an ending to a placeholder. A possessive takes «van»: «Apparaten van {name}».
2. Refer back with «deze persoon», never «hij» or «zij».
3. English singular "they" → «deze persoon», or drop it.

### 2.5 Fixed phrases
- Error pattern: «Bericht niet verstuurd. Controleer je verbinding en probeer het opnieuw.»
- "Check your connection and try again." → «Controleer je verbinding en probeer het opnieuw.»
- "Pull down to try again." → «Trek omlaag om het opnieuw te proberen.»
- "Could not X." → always «Kon … niet …»: «Kon de kamer niet maken.» "Cannot X." → «Kan … niet …».
- "Too many attempts." → «Te veel pogingen.» · "Something went wrong." → «Er ging iets mis.»
- "Nobody can undo this." → always «Niemand kan dit ongedaan maken.»
- Never «helaas», «sorry», «excuses», «succesvol» or «100% veilig».

### 2.6 Numbers, dates and units
- "{date} at {time}" → «{date} om {time}» · "Until {time}" → «Tot {time}» · "{days} days ago" → «{days} dagen geleden» (one: «{days} dag geleden») · "{page} of {total}" → «{page} van {total}».
- h → «uur»: «{hours} uur geleden». min and s stay.
- Dutch plurals have two cases: `one` is exactly 1, and 0 is `other`: «0 leden».

### 2.7 Ordinals
Dutch writes an ordinal as the number and «e». `securityOrdinal`: `{n, select, 1{1e} 2{2e} 3{3e} other{{n}e}}`. `settingsRecoveryWordLabel` → «{position} woord». `settingsRecoveryConfirmBody` → «Typ het {first} en {second} woord uit je bewaarde kopie.»

### 2.8 Platform labels
- Android: "Settings → Apps → Zuno → Language" → «Instellingen → Apps → Zuno → Taal».
- iOS: "Settings → General → Language & Region" → «Instellingen → Algemeen → Taal en regio»; «Locatievoorzieningen», «Privacy en beveiliging», the Photos app «Foto’s», and the notification settings «Meldingen», «Badges», «Bannerstijl», «Kritieke meldingen», «Directe berichten», «Toegangsscherm», «Berichtencentrum», «Geplande samenvatting», «Toon voorvertoningen», «Geluiden», «Tijdgevoelige meldingen», «Kondig meldingen aan».

---

## 3. Worked examples

| Key | English | nl |
|---|---|---|
| `settingsDeleteAccountWarningTitle` | Delete your account? | Je account verwijderen? |
| `feedbackNotSent` | Feedback not sent. Check your connection and try again. | Feedback niet verstuurd. Controleer je verbinding en probeer het opnieuw. |
| `chatNotSentRetry` | Not sent · Tap to retry | Niet verstuurd · Tik om opnieuw te proberen |
| `callsFailureOnAnotherDevice` | You are in this call on another device. Hang up there to join here. | Je zit al in deze oproep op een ander apparaat. Hang daar op om hier deel te nemen. |
| `settingsAccountPasswordChanged` | Password changed | Wachtwoord gewijzigd |
| `blockingTitle` | Block {name}? | {name} blokkeren? |
| `matrixStateNameChanged` | `{sender} changed the room name to \"{name}\"` | `{sender} heeft de kamernaam gewijzigd in ‘{name}’` |
| `matrixStateJoined` | `{count, plural, other{{people} joined}}` | `{count, plural, one{{people} is lid geworden} other{{people} zijn lid geworden}}` |
| `roomInfoIsConfirmed` | {name} is confirmed | {name} is bevestigd |
| `chatDeleteTitle` | `{count, plural, one{Delete message?} other{Delete {count} items?}}` | `{count, plural, one{Bericht verwijderen?} other{{count} items verwijderen?}}` |
| `matrixInvitePeopleInvited` | `{count, plural, other{{count} people invited}}` | `{count, plural, one{{count} persoon uitgenodigd} other{{count} personen uitgenodigd}}` |
| `permissionsPhotoLibraryAddUsage` | Zuno saves photos and videos to your library only when you tap Save. | Zuno bewaart foto’s en video’s alleen in je bibliotheek als je op ‘Opslaan’ tikt. |
