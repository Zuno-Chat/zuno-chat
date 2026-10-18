# Brand voice: Albanian (sq)

Albanian for `lib/l10n/app_sq.arb`, written in standard Albanian for Albania and Kosovo alike. The rules all languages share are in `translating.md`; this guide holds only what is Albanian.

**Binding, set by the product owner:**
- Address the reader as **ti**, lowercase: «Shkruaj kodin», «Mesazhet e tua», «të fton».
- Chat = **bisedë**, room = **dhomë**, community = **komunitet**. Never «grup», «kanal», «hapësirë» or the English «chat» for any of them.
- **Zuno**, **Matrix**, **Google**, **Apple**, **Android** and **iOS** never decline and never take a hyphenated ending: «në Zuno», «nga Zuno», «llogaria Google», «në rrjetin Matrix».
- `languageNativeName` → «Shqip».

---

## 1. Glossary

### 1.1 Brand-voice words

| English | sq | Notes |
|---|---|---|
| chat (one-to-one) | bisedë · biseda · bisedat | "New chat" → «Bisedë e re». The "Chats" tab → «Bisedat». |
| room (group chat) | dhomë · dhoma · dhomat | "New room" → «Dhomë e re». |
| community | komunitet · komuniteti · komunitetet | "New community" → «Komunitet i ri». |
| "Group with {names}" | «Bisedë: {names}» | |
| device | pajisje | Never «telefon» or «celular». |
| recovery code | kodi i rikuperimit | Never «çelës» or «fjalëkalim». |
| recovery | rikuperim | "Set up recovery" → «Konfiguro rikuperimin». |
| sign in | Identifikohu · identifikim | "New sign-in" → «Identifikim i ri». A signed-in device → «pajisje e identifikuar». |
| sign out | Dil · dalje | "Sign out everywhere else" → «Dil nga pajisjet e tjera». |
| sign up, sign-up code | Krijo llogari · regjistrim · kodi i regjistrimit | Push registration is «regjistrimi push». |
| server, homeserver | server | |
| Chat info / Room info / Community info | Detajet e bisedës / Detajet e dhomës / Detajet e komunitetit | |

### 1.2 People

| English | sq | Notes |
|---|---|---|
| person, people | person · personi · persona | The generic word for a human of any gender: «ky person», «këtij personi». |
| user / member | person / anëtar | "Unknown user" → «Person i panjohur». Never «përdorues» about a person; «emri i përdoruesit» (the field) is fine. «Anëtar» only in a role badge, a heading, an option label or a count (§2.4); in a sentence members are «personat»: "Search members" → «Kërko persona». |
| You (own name on tiles and the map) | Ti | |
| guest, stranger | vizitor · person i panjohur | |
| Someone / Anyone / Nobody / Everyone | Dikush / Kushdo / Askush / Të gjithë | "Anyone can join" → «Kushdo mund të bashkohet». |

### 1.3 Messaging

| English | sq | Notes |
|---|---|---|
| message | mesazh | Composer placeholder "Message" → «Mesazh». |
| send | Dërgo · dërgim | "Not sent" → «Nuk u dërgua». "Sending…" → «Po dërgohet…». |
| reply | Përgjigju · përgjigje | "Replying to {name}" → «Po i përgjigjesh: {name}». |
| reaction, react | reagim · reago | |
| edit, edited | Redakto · redaktuar | "(edited)" → «(redaktuar)». |
| delete | Fshi · fshirje | "Message deleted" → «Mesazhi u fshi». |
| remove (an item or a person) | Hiq · heqje | "Remove from room" → «Hiq nga dhoma». Never «fshi» for a person. |
| seen, seen by | Parë · Parë nga: {people} | "Not seen yet" → «Ende pa u parë». |
| typing | po shkruan… | "{name} is typing…" → «{name} po shkruan…». "Several people are typing…" → «Disa persona po shkruajnë…». |
| hidden (not shown) | nuk shfaqet | Never «fshihet», which is also the passive of «fshi» and reads as deleted. |
| mention | përmend · përmendje | "Mentions only" → «Vetëm përmendjet». |
| attachment, voice message | bashkëngjitje · mesazh zanor | |
| photo / video / file | foto / video / skedar | |
| media, item | media · element | The "Media" heading → «Media». "Delete 3 items?" → «Të fshihen 3 elemente?». |
| caption, gallery | mbishkrim · galeri | The iOS Photos app → «Photos» (§2.8). |
| history | historik | |
| record, upload, download, reload | regjistro · ngarko · shkarko · ringarko | "Uploading…" → «Po ngarkohet…». "Downloading…" → «Po shkarkohet…». "Loading…" is also «Po ngarkohet…»; context keeps them apart. |
| emoji, verification emoji | emoji · figura | |
| link | link · linku | Never «lidhje», which is the connection. |

### 1.4 Calls

| English | sq | Notes |
|---|---|---|
| call, voice call, video call | thirrje · thirrje zanore · thirrje me video | Button "Call" → «Thirr». |
| ring, ringtone, full screen | bie zilja · zile · ekran i plotë | |
| incoming / missed / ongoing call | thirrje hyrëse / e humbur / në vazhdim | "Missed call from {name}" → «Thirrje e humbur nga {name}». |
| Accept / Decline | Përgjigju / Refuzo (calls) · Prano / Refuzo (invites, requests) | |
| hang up, End call | Mbyll thirrjen | Both. «Mbyll» alone is Close. |
| join (a call) | Bashkohu | |
| speaker, mute, unmute | altoparlant · Hesht · Hiq heshtjen | "Muted" → «Heshtur». "{name} is muted" → «{name} e ka mikrofonin të heshtur». |
| camera, microphone | kamerë · mikrofon | |
| connection, connecting, reconnecting | lidhje · Po lidhet… · Po rilidhet… | "Weak connection" → «Lidhje e dobët». "Poor connection" → «Cilësi e ulët lidhjeje». "Calling…" → «Po thërret…». |
| picture-in-picture, minimize | figurë brenda figurës · Minimizo | |

### 1.5 Security and encryption

| English | sq | Notes |
|---|---|---|
| encryption, encrypted, decrypt | enkriptim · i enkriptuar · dekripto | |
| end-to-end encrypted | i enkriptuar nga skaji në skaj | |
| confirm (a person) | Konfirmo · konfirmim | "Confirmed people only" → «Vetëm persona të konfirmuar». |
| approve (own device) | Mirato · miratim | |
| verify, verification | verifiko · verifikim | |
| security details | të dhënat e sigurisë | |
| key, room keys | çelës · çelësat e dhomës | |
| backup, key backup, restore | kopje rezervë · kopje rezervë e çelësave · rikthe | |
| security key, security phrase, recovery key | çelës sigurie · frazë sigurie · çelës rikuperimi | |
| cross-signing, secret storage | nënshkrim i kryqëzuar · ruajtje e fshehtë | |
| session | sesion | |
| unlock, trust | shkyç · beso | |
| scan, QR code, code | Skano · kod QR · kod | "Scan code" → «Skano kodin». |
| screenshot, screen recording, screen sharing | pamje ekrani · regjistrim ekrani · ndarje ekrani | |
| block | Blloko / Zhblloko | |
| rooted device, compromised device | pajisje me root · pajisje e komprometuar | |
| clipboard, password manager | kujtesa e fragmenteve · menaxher fjalëkalimesh | |
| incognito keyboard | tastierë inkognito | |
| Cryptography | kriptografi | Encryption stays «enkriptim». |
| raw (security key), vouch for | i papërpunuar · mirato | |
| generate, export, import | gjenero · eksporto · importo | "Export room keys" → «Eksporto çelësat E2E të dhomave». |
| in person | ballë për ballë | |

### 1.6 Account, server and membership

| English | sq | Notes |
|---|---|---|
| account, password | llogari · fjalëkalim | "Wrong password." → «Fjalëkalim i gabuar.» "Confirm password" (the repeat field) → «Përsërit fjalëkalimin». |
| username, display name | emri i përdoruesit · emri i shfaqur | |
| profile, profile photo | profil · foto e profilit | |
| email address | adresa e email-it | |
| invite | Fto · ftesë | The "Invited" badge → «U ftua». |
| withdraw (an invitation) | Tërhiq ftesën · tërheqje e ftesës | Timeline: «{sender} tërhoqi ftesën: {people}», «{sender} ta tërhoqi ftesën». |
| join (a room or community) | Bashkohu · bashkim | "{people} joined" → «{people} u bashkua». |
| request, ask to join | kërkesë · Kërko të bashkohesh | "Let in" → «Lejo hyrjen». "Withdraw" → «Tërhiq kërkesën». The short "Ask" button → «Bëj kërkesë», since «Kërko» is Search; "Requested" → «Kërkesa u dërgua». |
| leave | Largohu · largim | "{people} left" → «{people} u largua». |
| ban | Dëbo / Hiq dëbimin · dëbim | "Banned" heading → «Persona të dëbuar». Never «blloko». Timeline: «{sender} dëboi: {people}», «{sender} hoqi dëbimin: {people}», «{sender} ta hoqi dëbimin». |
| report | Raporto · raportim | Reasons: «Ngacmim», «Përmbajtje e paligjshme», «Spam», «Arsye tjetër». |
| public / private | publik / privat | Agree with the noun described; a label serving both rooms and communities is «Qasje publike» / «Qasje private» / «Qasje me kërkesë» / «Qasje për komunitetin». "Make public" → «Cakto qasje publike». |
| topic, description, address, ID | temë · përshkrim · adresë · ID | Room alias → «adresa e dhomës». |
| hostname | emri i serverit | |

### 1.7 Roles and permissions

| English | sq | Notes |
|---|---|---|
| admin, moderator, owner | Administrator · Moderator · Pronar | Role badges only, never about a named person in a sentence: «{name} ka rolin “Administrator”». |
| role, member, read-only, view only | rol · Anëtar · Vetëm lexim · Vetëm shikim | |
| made (someone) an admin, You are now an admin | caktoi rolin “Administrator”: {people} · Tani ke rolin “Administrator” | A role change assigns the role by its quoted label, the same for every role. |
| defaults, default role | parazgjedhjet · roli i paracaktuar | "Room defaults" → «Parazgjedhjet e dhomës». |
| permission (room or OS), access | leje · qasje | "Roles & permissions" → «Rolet dhe lejet». Permission names are verbal nouns: "Remove people" → «Heqja e personave», "Change name" → «Ndryshimi i emrit». |

### 1.8 Notifications and push

| English | sq | Notes |
|---|---|---|
| notification, test notification | njoftim · njoftim prove | |
| push, push target, push key | push · destinacion push · çelës push | "push notifications" → «njoftime push». |
| registration (push) | regjistrim · regjistro | |
| delivery, background sync | shpërndarje · sinkronizim në sfond | "Delivery method" → «Mënyra e shpërndarjes». |
| battery use: Unrestricted / Optimized / Restricted | Përdorimi i baterisë: Pa kufizime / I optimizuar / I kufizuar | Android's labels. |
| Data Saver, Autostart | Kursyesi i të dhënave · Autostart | |
| distributor | shpërndarës | |
| Google services / Google Play services | shërbimet e Google / Shërbimet e Google Play | |
| Apple push | push i Apple | |
| gateway, bridge, token | portë · urë · token | «token-i», «token-in» (§2.3). |
| notification extension, crash | shtesa e njoftimeve · ndërprerje | "Crashed" → «U ndërpre». |
| diagnostics | diagnostikim | |
| notification category, notification shade | kategori njoftimesh · paneli i njoftimeve | |
| alert, security alerts | sinjalizim · Sinjalizimet e sigurisë | Never «njoftim», which is a notification. |
| lock screen | ekrani i kyçjes | Android's. The iOS diagnostics row stays English (§2.8). |
| quiet, sound, vibration | pa zë · tingull · dridhje | "Message tone" → «Tingulli i mesazhit». |
| standby bucket | grup gatishmërie | |

### 1.9 Location

| English | sq | Notes |
|---|---|---|
| location, live location | vendndodhje · vendndodhje e drejtpërdrejtë | |
| share, start / stop sharing | Ndaj · Fillo / Ndalo ndarjen | Also for sharing files. |
| approximate, maps app | e përafërt · aplikacion hartash | |

### 1.10 Settings, storage and data

| English | sq | Notes |
|---|---|---|
| Settings | Cilësimet | Zuno's and Android's. iOS's stays «Settings» inside an iOS path (§2.8). |
| storage, data, cache | hapësira e ruajtjes · të dhëna · memorie specifike | "Clear cache" → «Pastro memorien specifike». |
| theme: Dark / Light / Follow system | E errët / E çelët / Si sistemi | |
| Appearance / About / Advanced, version, build | Pamja / Rreth / Të avancuara · versioni · ndërtimi | |
| feedback, crash reports | koment · raporte ndërprerjesh | "Send feedback" → «Dërgo koment». |
| donate, privacy, Privacy policy, Terms | Dhuro · privatësi · Politika e privatësisë · Kushtet e përdorimit | |
| browser, underscore | shfletues · nënvizë | |
| app, home screen, shortcut, launcher | aplikacion · ekrani bazë · shkurtore · launcher | A chat app is «aplikacion mesazhesh». |
| recent apps, app switcher | aplikacionet e fundit · ndërruesi i aplikacioneve | |
| Open source licenses, Source code | Licencat me burim të hapur · Kodi burimor | |

### 1.11 Settled phrases

| English | sq | Notes |
|---|---|---|
| Asking to join (admin heading) | Kërkesa për t’u bashkuar | "Asking to join {name}" → «Kërkesa për t’u bashkuar: “{name}”». |
| Ask to join (subtitle) / Asks to join | Kërkojnë të bashkohen / Kërkon të bashkohet | The button stays «Kërko të bashkohesh». |
| Let them ask (setting) | Lejo kërkesat | |
| Joined (label on a public room or community) | U bashkove | |
| N other(s) | {count} person tjetër · {count} persona të tjerë | one · other. |
| Name lists: {first} and {second} / {first}, {second} and {third} | {first} dhe {second} / {first}, {second} dhe {third} | A list takes a plural verb («{people} u bashkuan»), a single name (`one`) a singular. |
| asleep (device) / suspended (app) | në gjumë / i pezulluar | They agree with «pajisje» and «aplikacion». |
| Call rang / ringing | Ra zilja / Po bie zilja | |
| Hidden message | mesazh i fshehur | Never «i fshehtë». |
| Secure backup (screen) | “Rikuperimi” | |
| Welcome to Zuno | Mirë se erdhe në Zuno | |
| With {name} / In {name} (room) / {name}'s devices | Bisedë: {name} / Në dhomën “{name}” / Pajisjet: {name} | |
| {name} is confirmed | {name} është konfirmuar | A compound tense, so nothing agrees with the person (§2.4). |
| character(s), check mark | karakter · shenjë zgjedhjeje | |

### 1.12 UI actions

| English | sq |
|---|---|
| Cancel / Save / Saved | Anulo / Ruaj / U ruajt |
| Delete / Remove (item) / Remove (person) | Fshi / Hiq / Hiq |
| Copy / Copied / Share | Kopjo / U kopjua / Ndaj |
| Send / Continue / Continue anyway | Dërgo / Vazhdo / Vazhdo gjithsesi |
| Done / Retry / Try again | U krye / Riprovo / Provo sërish |
| Close / Dismiss / Open / Open settings | Mbyll / Fshih / Hap / Hap cilësimet |
| Turn on / Turn off · On / Off | Aktivizo / Çaktivizo · Aktiv / Joaktiv |
| Allow / Not now / Skip | Lejo / Jo tani / Kapërce |
| Confirm / Approve | Konfirmo / Mirato |
| Create / Start / Get started | Krijo / Fillo / Fillo |
| Edit / Change / Review | Redakto / Ndrysho / Rishiko |
| Back / Stop / Play | Prapa / Ndalo / Luaj |
| Read more / Show less | Shfaq më shumë / Shfaq më pak |
| Mark as read / Unread | Shëno si të lexuar / Të palexuara |
| Refresh / Search / Start over | Rifresko / Kërko / Fillo nga e para |

### 1.13 Status words

| English | sq |
|---|---|
| Loading… / Sending… / Waiting… | Po ngarkohet… / Po dërgohet… / Në pritje… |
| Checking… / Searching… | Po kontrollohet… / Po kërkohet… |
| Failed | Dështoi |
| Not set / Unknown / None / Never | Pa caktuar / I panjohur (agrees with its noun) / Asnjë / Kurrë |
| Not available (a feature) / Unavailable (a thing) | Nuk ofrohet / Nuk është i/e disponueshëm |
| Yes / No / Status | Po / Jo / Gjendja |
| Just now / Today / Yesterday / Coming soon | Tani / Sot / Dje / Së shpejti |

---

## 2. Albanian rules

### 2.1 Register
- «ti» throughout, lowercase, with its possessives after the noun: «kodi yt», «llogaria jote», «çelësat e tu», «pajisjet e tua».
- Drop the possessive where Albanian does: «Kontrollo lidhjen», not «Kontrollo lidhjen tënde».
- "tap" → «prek», "type" and "enter" → «shkruaj», "choose/pick" → «zgjidh», "pull down" → «tërhiq poshtë», "swipe" → «rrëshqit».
- Write «nuk», never the clipped «s’». Where Albanian needs an apostrophe («t’u», «t’i»), it is the typographic ’.

### 2.2 Forms

| Where | Form | Example |
|---|---|---|
| Buttons, menu items, tooltips, actions in rows | Imperative (ti) | «Fshi llogarinë», «Ruaj», «Aktivizo altoparlantin» |
| Tabs, switches and labels that name a thing | Noun, definite | «Bisedat», «Njoftimet», «Altoparlanti» |
| Body text, hints, the next step in an error | Imperative (ti) | «Prek për të provuar sërish.» |
| Titles that name something | Noun phrase, definite | «Cilësimet e dhomës», «Pajisjet e tua» |
| Titles that instruct | Imperative | «Ruaj kodin e rikuperimit» |
| Confirmation titles ("Delete X?") | «Të» + passive subjunctive + «?»; leaving and signing out, which have no passive, take the ti form | «Të fshihet llogaria?», «Të dalësh nga llogaria?» |
| Progress labels | «Po» + passive present + «…» | «Po krijohet llogaria…», «Po dërgohet…» |
| Success snack bars | Passive past with «u» | «Fjalëkalimi u ndryshua», «Raporti u dërgua» |

Statement and first-person buttons: «Përputhen», «Nuk përputhen», «Po, mbylle», «Jo, anuloje», «Kam tashmë një kod».

### 2.3 Typography
- Always «ë» and «ç»; never «e» or «c» in their place.
- Quotes: “…” (U+201C, U+201D), and ‘…’ inside them: `“{name}”`.
- No space before «?», «!», «:», «;» or «%».
- A foreign word or acronym that takes an ending gets a hyphen: «email-i», «PIN-i». Words Albanian has absorbed take endings directly: «serveri», «linku». Brand names never take one (binding choices).
- Colons stay exactly as in the English, plus the name colons of §2.4.

### 2.4 Names
Albanian marks gender in adjectives and participles that take the article «i/e» («i konfirmuar/e konfirmuar», «i sigurt/e sigurt») and in nouns for people («anëtar/anëtare», «përdorues/përdoruese»). A name also changes its ending outside the nominative («me Anën», «pajisjet e Anës»). Verb tenses never mark gender, and neither does the participle in a compound tense («është konfirmuar», «je identifikuar»).

1. A name stays in the nominative: as the subject («{name} po shkruan…»), after «nga», which takes the nominative («Thirrje e humbur nga {name}»), or after a colon («Bisedë: {name}», «Po i përgjigjesh: {name}»). Never after another preposition, as an object or as a possessive.
2. Timeline events take the past tense: «{sender} ndryshoi emrin e dhomës në “{name}”», «{people} u bashkua», «{people} u largua». A second name goes after a colon: «{sender} ftoi: {people}», «{sender} hoqi nga dhoma: {people}».
3. A state takes a compound tense or a phrase whose words agree with a thing: «{name} është konfirmuar», «{name} e ka mikrofonin të heshtur», «{name} ka të dhëna të reja sigurie». Never «{name} është i/e…».
4. The reader takes any tense («Nuk je më në këtë dhomë», «Je identifikuar», «U largove»), never an «i/e» adjective or participle: "Are you sure?" is recast as a question about the action («Do ta fshish?»), never «Je i sigurt?».
5. A noun for a person in a sentence is «person», never «anëtar», «administrator» or «përdorues» about someone named or the reader.
6. Once the name has appeared, refer back with «ky person», «këtij personi»: "Scan {name}'s code" → «Skano kodin: {name}», and later «kodin e këtij personi».
7. English singular "they" → «ky person», or drop it.
8. Never a doublet such as «i/e», «(e)» or «-e».

### 2.5 Fixed phrases
- Error pattern: «Mesazhi nuk u dërgua. Kontrollo lidhjen dhe provo sërish.»
- "Check your connection and try again." → «Kontrollo lidhjen dhe provo sërish.»
- "Pull down to try again." → «Tërhiq poshtë për të provuar sërish.»
- "Too many attempts." → «Shumë përpjekje.» · "Something went wrong." → «Diçka shkoi keq.»
- "Nobody can undo this." → always «Askush nuk mund ta zhbëjë këtë.»
- Never «Fatkeqësisht», «Na vjen keq», «Kërkojmë ndjesë», «me sukses» or «100% i sigurt».

### 2.6 Numbers, dates and units
- "{date} at {time}" → «{date} në {time}» · "Until {time}" → «Deri në {time}» · "{days} days ago" → «{days} ditë më parë» · "{page} of {total}" → «{page} nga {total}».
- h → «orë»: «{hours} orë më parë». min and s stay.
- Albanian plurals have two cases: `one` is exactly 1, and 0 is `other`: «0 anëtarë». Add `one` where `translating.md` lists it, unless the noun is the same in both: «ditë», «orë».

### 2.7 Ordinals
Albanian writes the recovery-word position as a plain number after «fjala», so `securityOrdinal` drops the ending: `{n, select, 1{1} 2{2} 3{3} other{{n}}}`. `settingsRecoveryWordLabel` → «Fjala {position}». `settingsRecoveryConfirmBody` → «Shkruaj fjalët {first} dhe {second} nga kopja që ke ruajtur.»

### 2.8 Platform labels
- Android shows Albanian, so its labels are translated as Android shows them: "Settings → Apps → Zuno → Language" → «Cilësimet → Aplikacionet → Zuno → Gjuha».
- iOS has no Albanian interface, so an Albanian reader's iPhone shows another language, most often English. Names of iOS's own screens, settings and apps stay exactly as the English strings write them, quoted with “…” inside a sentence: «“Settings → General → Language & Region”», «“Location Services”», «“Privacy & Security”», the Photos app «“Photos”». The push diagnostics rows whose description names an iPhone notification setting («Lock screen», «Show previews» and the rest) keep their English text unchanged. Zuno's own buttons stay Albanian: «Hap cilësimet».

---

## 3. Worked examples

| Key | English | sq |
|---|---|---|
| `settingsDeleteAccountWarningTitle` | Delete your account? | Të fshihet llogaria? |
| `feedbackNotSent` | Feedback not sent. Check your connection and try again. | Komenti nuk u dërgua. Kontrollo lidhjen dhe provo sërish. |
| `chatNotSentRetry` | Not sent · Tap to retry | Nuk u dërgua · Prek për të riprovuar |
| `callsFailureOnAnotherDevice` | You are in this call on another device. Hang up there to join here. | Je në këtë thirrje në një pajisje tjetër. Mbyll thirrjen atje për t’u bashkuar këtu. |
| `settingsAccountPasswordChanged` | Password changed | Fjalëkalimi u ndryshua |
| `blockingTitle` | Block {name}? | Të bllokohet {name}? |
| `matrixStateNameChanged` | `{sender} changed the room name to \"{name}\"` | `{sender} ndryshoi emrin e dhomës në “{name}”` |
| `matrixStateInvited` | {sender} invited {people} | {sender} ftoi: {people} |
| `roomInfoIsConfirmed` | {name} is confirmed | {name} është konfirmuar |
| `chatDeleteTitle` | `{count, plural, one{Delete message?} other{Delete {count} items?}}` | `{count, plural, one{Të fshihet mesazhi?} other{Të fshihen {count} elemente?}}` |
| `matrixInvitePeopleInvited` | `{count, plural, other{{count} people invited}}` | `{count, plural, one{U ftua {count} person} other{U ftuan {count} persona}}` |
| `settingsLanguageAddStep` | 1. Add the language in Settings → General → Language & Region. | 1. Shto gjuhën te “Settings → General → Language & Region”. |
| `permissionsPhotoLibraryAddUsage` | Zuno saves photos and videos to your library only when you tap Save. | Zuno i ruan fotot dhe videot në bibliotekën tënde vetëm kur prek “Ruaj”. |
