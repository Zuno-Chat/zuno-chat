# Brand voice: Norwegian Bokmål (nb)

Norwegian Bokmål for `lib/l10n/app_nb.arb`, written for Norway. The rules all languages share are in `translating.md`; this guide holds only what is Norwegian.

**Binding, set by the product owner:**
- Address the reader as **du**, lowercase: «Skriv inn koden», «Meldingene dine», «inviterer deg».
- Chat = **chat**, room = **rom**, community = **fellesskap**. Never «gruppe», «kanal», «samtale» or «space» for any of them.
- **Zuno**, **Matrix**, **Google**, **Apple**, **Android** and **iOS** never take an ending; a possessive is recast with «i Zuno» or «fra Zuno». In compounds they take a hyphen («Google-konto», «Matrix-server»).
- Bokmål only; Nynorsk is not offered. `languageNativeName` → «Norsk bokmål».

---

## 1. Glossary

### 1.1 Brand-voice words

| English | nb | Notes |
|---|---|---|
| chat (one-to-one) | chat · chatten · chatter | "New chat" → «Ny chat». The "Chats" tab → «Chatter». |
| room (group chat) | rom · rommet · rom | "New room" → «Nytt rom». |
| community | fellesskap · fellesskapet · fellesskap | "New community" → «Nytt fellesskap». |
| "Group with {names}" | «Chat med {names}» | |
| Chat info / Room info / Community info | Chatinfo / Rominfo / Info om fellesskapet | |
| device | enhet · enheten · enheter | Never «telefon» or «mobil». |
| recovery code | gjenopprettingskode | Never «nøkkel» or «passord». |
| recovery | gjenoppretting | "Set up recovery" → «Konfigurer gjenoppretting». |
| sign in | Logg på · pålogging | "New sign-in" → «Ny pålogging». A signed-in device → «pålogget enhet». |
| sign out | Logg av | "Sign out everywhere else" → «Logg av alle andre enheter». |
| sign up, sign-up code | Opprett konto · registrering · registreringskode | Push registration is «push-registrering». |
| server, homeserver | server | |

### 1.2 People

| English | nb | Notes |
|---|---|---|
| person, people | person · personer | «personen», «denne personen». |
| user / member | person / medlem | "Unknown user" → «Ukjent person». Never «bruker» about a person; «brukernavn» (the field) is fine. "Search members" → «Søk etter medlemmer». |
| You (own name on tiles and the map) | Du | |
| Someone / Anyone / Nobody / Everyone | Noen / Alle / Ingen / Alle | "Anyone can join" → «Alle kan bli med». |
| guest, stranger | gjest · en fremmed | |

### 1.3 Messaging

| English | nb | Notes |
|---|---|---|
| message | melding · meldingen · meldinger | Composer placeholder "Message" → «Melding». |
| send | Send | "Not sent" → «Ikke sendt». "Sending…" → «Sender…». |
| reply | Svar | "Replying to {name}" → «Svarer {name}». |
| reaction, react | reaksjon · reager | |
| edit, edited | Rediger · redigert | "(edited)" → «(redigert)». |
| delete | Slett · sletting | "Message deleted" → «Melding slettet». |
| remove (an item or a person) | Fjern | "Remove from room" → «Fjern fra rommet». Never «slett» for a person. |
| hidden (not shown) | skjult · vises ikke | |
| seen, seen by | Sett · Sett av: {people} | "Not seen yet" → «Ikke sett ennå». |
| typing | skriver… | "{name} is typing…" → «{name} skriver…». "Several people are typing…" → «Flere personer skriver…». |
| mention | nevne · omtale | "Mentions only" → «Bare omtaler». |
| attachment, voice message | vedlegg · talemelding | |
| photo / video / file | bilde / video / fil | |
| media, item | medier · element | The "Media" heading → «Medier». "Delete 3 items?" → «Slette 3 elementer?». |
| caption, gallery | bildetekst · galleri | iOS Photos app → «Bilder». |
| history | historikk | |
| record, upload, download, reload | ta opp · last opp · last ned · last inn på nytt | "Uploading…" → «Laster opp…». "Downloading…" → «Laster ned…». «Laster inn…» is Loading only. |
| emoji, verification emoji | emoji · bilder | |
| link | lenke | |

### 1.4 Calls

| English | nb | Notes |
|---|---|---|
| call, voice call, video call | anrop · taleanrop · videoanrop | Button "Call" → «Ring». |
| ring, ringtone, full screen | ringe · ringetone · fullskjerm | |
| incoming / missed / ongoing call | innkommende / tapt / pågående anrop | "Missed call from {name}" → «Tapt anrop fra {name}». |
| Accept / Decline | Svar / Avvis (calls) · Godta / Avslå (invites, requests) | |
| hang up, End call | Legg på | Both. |
| join (a call) | Bli med | |
| speaker, mute, unmute | høyttaler · Slå av lyd · Slå på lyd | "Muted" → «Lyd av». "{name} is muted" → «{name} har slått av lyden». |
| camera, microphone | kamera · mikrofon | |
| connection, connecting, reconnecting | tilkobling · Kobler til… · Kobler til på nytt… | "Weak connection" → «Svak tilkobling». "Poor connection" → «Dårlig tilkoblingskvalitet». "Calling…" → «Ringer…». |
| picture-in-picture, minimize | bilde-i-bilde · Minimer | |

### 1.5 Security and encryption

| English | nb | Notes |
|---|---|---|
| encryption, encrypted, decrypt | kryptering · kryptert · dekrypter | |
| end-to-end encrypted | ende-til-ende-kryptert | |
| confirm (a person) | Bekreft · bekreftelse | "Confirmed people only" → «Bare bekreftede personer». |
| approve (own device) | Godkjenn · godkjenning | |
| verify, verification | verifiser · verifisering | |
| security details | sikkerhetsopplysninger | |
| key, room keys | nøkkel · romnøkler | |
| backup, key backup, restore | sikkerhetskopi · sikkerhetskopi av nøkler · gjenopprett | |
| security key, security phrase, recovery key | sikkerhetsnøkkel · sikkerhetsfrase · gjenopprettingsnøkkel | |
| cross-signing, secret storage | kryss-signering · hemmelig lager | |
| session | økt | |
| unlock, trust | lås opp · stole på | |
| scan, QR code, code | Skann · QR-kode · kode | "Scan code" → «Skann koden». |
| screenshot, screen recording, screen sharing | skjermbilde · skjermopptak · skjermdeling | |
| block | Blokker / Opphev blokkering | |
| rooted device, compromised device | rootet enhet · kompromittert enhet | |
| clipboard, password manager | utklippstavle · passordbehandler | |
| incognito keyboard | inkognitotastatur | |
| Cryptography | kryptografi | Encryption stays «kryptering». |
| raw (security key), vouch for | rå · godkjenne | |
| generate, export, import, in person | generer · eksporter · importer · ansikt til ansikt | |

### 1.6 Account, server and membership

| English | nb | Notes |
|---|---|---|
| account, password | konto · passord | "Wrong password." → «Feil passord.» "Confirm password" (the repeat field) → «Gjenta passordet». |
| username, display name | brukernavn · visningsnavn | |
| profile, profile photo | profil · profilbilde | |
| email address | e-postadresse | |
| invite | Inviter · invitasjon | The "Invited" badge → «Invitert». |
| withdraw (an invitation) | trekke tilbake invitasjonen | "{sender} withdrew your invitation" → «{sender} trakk tilbake invitasjonen din». |
| join (a room or community) | Bli med | "{people} joined" → «{people} ble med». "Joined and left" → «ble med og gikk igjen». |
| request, ask to join | forespørsel · Be om å bli med | Short "Ask" button → «Spør». "Requested" → «Forespurt». "Let in" → «Slipp inn». "Withdraw" → «Trekk tilbake». |
| leave | Forlat | "{people} left" → «{people} gikk». |
| ban | Utesteng / Opphev utestengelse · utestengelse | "Banned" heading → «Utestengte». "{sender} unbanned {people}" → «{sender} opphevet utestengelsen av {people}». Never «blokker». |
| report | Rapporter · rapport | Reasons: «Trakassering», «Ulovlig innhold», «Spam», «Annen årsak». |
| public / private | offentlig / privat | Agree with the noun («et offentlig rom», «et privat fellesskap»); a label serving both is «Offentlig tilgang» / «Privat tilgang» / «Tilgang etter forespørsel» / «Tilgang for fellesskapet». "Make public" → «Gjør offentlig». |
| topic, description, address, ID | emne · beskrivelse · adresse · ID | Room alias → «romadresse». |
| hostname | servernavn | |
| defaults, default role | standardinnstillinger · standardrolle | |

### 1.7 Roles and permissions

| English | nb | Notes |
|---|---|---|
| admin, moderator, owner | Administrator · Moderator · Eier | |
| role, member, read-only, view only | rolle · Medlem · Bare lesing · Bare visning | |
| give a role ("made {people} an admin", "you are now an admin") | gi {people} rollen «…» · Du har nå rollen «…» | With the role's label, the same for every role, since «Bare lesing» is no person noun. |
| permission (room or OS), access | tillatelse · tilgang | "Roles & permissions" → «Roller og tillatelser». Permission names are infinitives: "Remove people" → «Fjerne personer», "Change name" → «Endre navn». |

### 1.8 Notifications and push

| English | nb | Notes |
|---|---|---|
| notification, test notification | varsel · varselet · varsler · testvarsel | |
| alert, security alerts | varsel · sikkerhetsvarsler | The same word as notification; call alerts → «anropsvarsler». |
| push, push target, push key | push · push-mål · push-nøkkel | "push notifications" → «push-varsler». |
| registration (push) | registrering · registrer | |
| delivery, background sync | levering · bakgrunnssynkronisering | "Delivery method" → «Leveringsmetode». |
| battery use: Unrestricted / Optimized / Restricted | Batteribruk: Ubegrenset / Optimalisert / Begrenset | Android's labels. |
| Data Saver, Autostart | Datasparing · Autostart | |
| distributor | distributør | |
| Google services / Google Play services | Google-tjenester / Google Play-tjenester | |
| Apple push | Apple-push | |
| gateway, bridge, token | gateway · bro · token | |
| notification extension, crash | varselutvidelse · krasj | "Crashed" → «Krasjet». |
| diagnostics | diagnostikk | |
| notification category, notification shade | varselkategori · varselpanelet | |
| lock screen | låseskjerm | |
| quiet, sound, vibration | lydløs · lyd · vibrering | "Message tone" → «Meldingslyd». |
| standby bucket | standbygruppe | |

### 1.9 Location

| English | nb | Notes |
|---|---|---|
| location, live location | posisjon · sanntidsposisjon | |
| share, start / stop sharing | Del · Start / Stopp deling | Also for sharing files. |
| approximate, maps app | omtrentlig · kartapp | |

### 1.10 Settings, storage and data

| English | nb | Notes |
|---|---|---|
| Settings | Innstillinger | Zuno's, Android's and iOS's. |
| storage, data, cache | lagring · data · buffer | "Clear cache" → «Tøm bufferen». "Data & storage" → «Data og lagring». |
| theme: Dark / Light / Follow system | Mørkt / Lyst / Følg systemet | |
| Appearance / About / Advanced, version, build | Utseende / Om / Avansert · versjon · build | |
| feedback, crash reports | tilbakemelding · krasjrapporter | "Send feedback" → «Send tilbakemelding». |
| donate, privacy, Privacy policy, Terms | Doner · personvern · Personvernerklæring · Vilkår | |
| browser, underscore | nettleser · understrek | |
| app, home screen, shortcut, launcher | app · startskjerm · snarvei · launcher | A chat app is «meldingsapp». |
| recent apps, app switcher | nylige apper · appveksleren | |
| Open source licenses, Source code | Lisenser for åpen kildekode · Kildekode | |

### 1.11 Settled phrases

| English | nb | Notes |
|---|---|---|
| Asking to join (admin heading) | Forespørsler om å bli med | "Asking to join {name}" → «Forespørsler om å bli med i «{name}»». |
| Ask to join (subtitle under "{name} and N others") / Asks to join | Ber om å bli med / Ber om å bli med | Both mean the people named are asking. The button stays «Be om å bli med». |
| Let them ask (setting) | Tillat forespørsler | |
| Joined (label on a public room or community) | Medlem | |
| N other(s) | {count} annen · {count} andre | one · other. |
| asleep (device) / suspended (app) | i dvale / satt på pause | |
| Call rang / ringing | Ringte / Ringer | |
| Hidden message | skjult melding | Never «hemmelig». |
| Secure backup (screen) | «Gjenoppretting» | |
| Welcome to Zuno | Velkommen til Zuno | |
| With {name} / In {name} (room) / {name}'s devices | Med {name} / I rommet «{name}» / Enhetene til {name} | |
| {name} is confirmed | {name} er bekreftet | |
| character(s), check mark | tegn · hake | |
| reinstall, sign-in code, the verification check | reinstallering · påloggingskode · kontrollen | |
| "{type} event", bootloader | «Hendelse: {type}» · oppstartslaster | |

### 1.12 UI actions

| English | nb |
|---|---|
| Cancel / Save / Saved | Avbryt / Lagre / Lagret |
| Delete / Remove | Slett / Fjern |
| Copy / Copied / Share | Kopier / Kopiert / Del |
| Send / Continue / Continue anyway | Send / Fortsett / Fortsett likevel |
| Done / Retry / Try again | Ferdig / Prøv igjen / Prøv igjen |
| Close / Dismiss / Open / Open settings | Lukk / Avvis / Åpne / Åpne innstillinger |
| Turn on / Turn off · On / Off | Slå på / Slå av · På / Av |
| Allow / Not now / Skip | Tillat / Ikke nå / Hopp over |
| Confirm / Approve | Bekreft / Godkjenn |
| Create / Start / Get started | Opprett / Start / Kom i gang |
| Edit / Change / Review | Rediger / Endre / Se gjennom |
| Back / Stop / Play | Tilbake / Stopp / Spill av |
| Read more / Show less | Vis mer / Vis mindre |
| Mark as read / Unread | Merk som lest / Ulest |
| Refresh / Search / Start over | Oppdater / Søk / Begynn på nytt |

### 1.13 Status words

| English | nb |
|---|---|
| Loading… / Sending… / Waiting… | Laster inn… / Sender… / Venter… |
| Checking… / Searching… | Sjekker… / Søker… |
| Failed | Mislyktes |
| Not set / Unknown / None / Never | Ikke angitt / Ukjent / Ingen / Aldri |
| Not available / Yes / No / Status | Ikke tilgjengelig / Ja / Nei / Status |
| Just now / Today / Yesterday / Coming soon | Akkurat nå / I dag / I går / Kommer snart |

---

## 2. Norwegian rules

### 2.1 Register
- «du» throughout, lowercase: «du», «deg», «din», «ditt», «dine», with the possessive after the noun as Norwegian prefers: «meldingene dine». Never «De».
- Drop the possessive where Norwegian does: «Sjekk tilkoblingen».
- "tap" → «trykk på», "type" and "enter" → «skriv inn» or «angi», "choose/pick" → «velg», "pull down" → «dra ned», "swipe" → «sveip».

### 2.2 Forms

| Where | Form | Example |
|---|---|---|
| Buttons, menu items, tooltips, actions in rows | Imperative | «Slett konto», «Lagre», «Slå på høyttaleren» |
| Tabs, switches and labels that name a thing | Noun | «Chatter», «Varsler», «Høyttaler» |
| Body text, hints, the next step in an error | Imperative | «Trykk for å prøve igjen.» |
| Titles that name something | Noun | «Rominnstillinger», «Enhetene dine» |
| Titles that instruct | Imperative | «Lagre gjenopprettingskoden» |
| Confirmation titles ("Delete X?") | Infinitive + «?» | «Slette kontoen?» |
| Progress labels | Present tense + «…» | «Oppretter konto…», «Sender…» |
| Success snack bars | Noun + participle | «Passord endret», «Rapport sendt» |

Statement and first-person buttons: «De samsvarer», «De samsvarer ikke», «Ja, fullfør», «Nei, stopp», «Jeg har allerede en kode».

### 2.3 Typography
- Quotes: «…» (U+00AB, U+00BB), and ‘…’ inside them: `«{name}»`.
- No space before «?», «!», «:» or «;».
- Apostrophe: typographic ’ only.
- Compounds are written as one word; after an acronym or a brand they take a hyphen: «QR-kode», «Google-konto», «push-varsel». Where three equal consonants meet, use a hyphen: «kryss-signering».

### 2.4 Names
Norwegian marks no gender on verbs or adjectives for people, so «{name} er bekreftet» is safe. Two things are not safe: the pronouns «han/hun», and an ending on a name («Annas enheter»).

1. Never attach an ending to a placeholder. A possessive takes «til»: «Enhetene til {name}».
2. Refer back with «personen» or «denne personen», never «han», «hun» or «hen».
3. English singular "they" → «personen», or drop it.

### 2.5 Fixed phrases
- Error pattern: «Meldingen ble ikke sendt. Sjekk tilkoblingen og prøv igjen.»
- "Check your connection and try again." → «Sjekk tilkoblingen og prøv igjen.»
- "Pull down to try again." → «Dra ned for å prøve igjen.»
- "Could not X." → «Kunne ikke X.» as a short label, «Det gikk ikke å X.» when more sentences follow.
- "Too many attempts." → «For mange forsøk.» · "Something went wrong." → «Noe gikk galt.»
- "Nobody can undo this." → always «Ingen kan angre dette.»
- Never «dessverre», «beklager», «unnskyld», «vellykket» or «100 % sikker».

### 2.6 Numbers, dates and units
- "{date} at {time}" → «{date} kl. {time}» · "Until {time}" → «Til {time}» · "{days} days ago" → «for {days} dager siden» (one: «for {days} dag siden») · "{page} of {total}" → «{page} av {total}».
- h → «t»: «for {hours} t siden». min and s stay.
- Norwegian plurals have two cases: `one` is exactly 1, and 0 is `other`: «0 medlemmer».

### 2.7 Ordinals
Norwegian writes an ordinal as the number and a full stop. `securityOrdinal`: `{n, select, 1{1.} 2{2.} 3{3.} other{{n}.}}`. `settingsRecoveryWordLabel` → «{position} ord». `settingsRecoveryConfirmBody` → «Skriv inn det {first} og {second} ordet fra den lagrede kopien.»

### 2.8 Platform labels
- Android: "Settings → Apps → Zuno → Language" → «Innstillinger → Apper → Zuno → Språk».
- iOS: "Settings → General → Language & Region" → «Innstillinger → Generelt → Språk og region»; «Stedstjenester», «Personvern og sikkerhet», the Photos app «Bilder», and the notification settings «Varsler», «Merker», «Bannerstil», «Kritiske varsler», «Direktemeldinger», «Låseskjerm», «Varslingssenter», «Planlagt sammendrag», «Vis forhåndsvisninger», «Lyder», «Tidssensitive varslinger», «Les opp varslinger».

---

## 3. Worked examples

| Key | English | nb |
|---|---|---|
| `settingsDeleteAccountWarningTitle` | Delete your account? | Slette kontoen din? |
| `feedbackNotSent` | Feedback not sent. Check your connection and try again. | Tilbakemeldingen ble ikke sendt. Sjekk tilkoblingen og prøv igjen. |
| `chatNotSentRetry` | Not sent · Tap to retry | Ikke sendt · Trykk for å prøve igjen |
| `callsFailureOnAnotherDevice` | You are in this call on another device. Hang up there to join here. | Du er med i anropet på en annen enhet. Legg på der for å bli med her. |
| `settingsAccountPasswordChanged` | Password changed | Passord endret |
| `blockingTitle` | Block {name}? | Blokkere {name}? |
| `matrixStateNameChanged` | `{sender} changed the room name to \"{name}\"` | `{sender} endret navnet på rommet til «{name}»` |
| `matrixStateInvited` | `{count, plural, other{{sender} invited {people}}}` | `{count, plural, other{{sender} inviterte {people}}}` |
| `roomInfoIsConfirmed` | {name} is confirmed | {name} er bekreftet |
| `chatDeleteTitle` | `{count, plural, one{Delete message?} other{Delete {count} items?}}` | `{count, plural, one{Slette meldingen?} other{Slette {count} elementer?}}` |
| `matrixInvitePeopleInvited` | `{count, plural, other{{count} people invited}}` | `{count, plural, one{{count} person invitert} other{{count} personer invitert}}` |
| `permissionsPhotoLibraryAddUsage` | Zuno saves photos and videos to your library only when you tap Save. | Zuno lagrer bilder og videoer i biblioteket ditt bare når du trykker på «Lagre». |
