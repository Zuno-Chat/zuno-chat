# Brand voice: Swedish (sv)

Swedish for `lib/l10n/app_sv.arb`, written for Sweden. The rules all languages share are in `translating.md`; this guide holds only what is Swedish.

**Binding, set by the product owner:**
- Address the reader as **du**, lowercase: «Skriv koden», «Dina meddelanden», «bjuder in dig».
- Chat = **chatt**, room = **rum**, community = **gemenskap**. Never «grupp», «kanal», «konversation», «utrymme» or the English «chat» for any of them.
- **Zuno**, **Matrix**, **Google**, **Apple**, **Android** and **iOS** never take an ending; a possessive is recast with «i Zuno» or «från Zuno». In compounds they take a hyphen («Google-konto», «Matrix-server»).
- `languageNativeName` → «Svenska».

---

## 1. Glossary

### 1.1 Brand-voice words

| English | sv | Notes |
|---|---|---|
| chat (one-to-one) | chatt · chatten · chattar | "New chat" → «Ny chatt». The "Chats" tab → «Chattar». |
| room (group chat) | rum · rummet · rum | "New room" → «Nytt rum». |
| community | gemenskap · gemenskapen · gemenskaper | "New community" → «Ny gemenskap». |
| "Group with {names}" | «Chatt med {names}» | |
| Chat info / Room info / Community info | Chattinfo / Rumsinfo / Info om gemenskapen | |
| device | enhet · enheten · enheter | Never «telefon» or «mobil». |
| recovery code | återställningskod | Never «nyckel» or «lösenord». |
| recovery | återställning | "Set up recovery" → «Konfigurera återställning». |
| sign in | Logga in · inloggning | "New sign-in" → «Ny inloggning». A signed-in device → «inloggad enhet». |
| sign out | Logga ut | "Sign out everywhere else" → «Logga ut från alla andra enheter». |
| sign up, sign-up code | Skapa konto · registrering · registreringskod | Push registration is «push-registrering». |
| server, homeserver | server | |

### 1.2 People

| English | sv | Notes |
|---|---|---|
| person, people | person · personer | «personen», «den här personen». |
| user / member | person / medlem | "Unknown user" → «Okänd person». Never «användare» about a person; «användarnamn» (the field) is fine. "Search members" → «Sök bland medlemmar». |
| You (own name on tiles and the map) | Du | |
| Someone / Anyone / Nobody / Everyone | Någon / Alla / Ingen / Alla | "Anyone can join" → «Alla kan gå med». |
| guest, stranger | gäst · en främling | |

### 1.3 Messaging

| English | sv | Notes |
|---|---|---|
| message | meddelande · meddelandet · meddelanden | Composer placeholder "Message" → «Meddelande». |
| send | Skicka | "Not sent" → «Inte skickat». "Sending…" → «Skickar…». |
| reply | Svara | "Replying to {name}" → «Svarar {name}». |
| reaction, react | reaktion · reagera | |
| edit, edited | Redigera · redigerat | "(edited)" → «(redigerat)». |
| delete | Radera · radering | "Message deleted" → «Meddelandet raderat». |
| remove (an item or a person) | Ta bort | "Remove from room" → «Ta bort från rummet». Never «radera» for a person. |
| hidden (not shown) | dold · visas inte | |
| seen, seen by | Sett · Sett av: {people} | "Not seen yet" → «Inte sett än». |
| typing | skriver… | "{name} is typing…" → «{name} skriver…». "Several people are typing…" → «Flera personer skriver…». |
| mention | nämna · omnämnande | "Mentions only" → «Endast omnämnanden». |
| attachment, voice message | bilaga · röstmeddelande | |
| photo / video / file | bild / video / fil | |
| media, item | media · objekt | The "Media" heading → «Media». "Delete 3 items?" → «Radera 3 objekt?». |
| caption, gallery | bildtext · galleri | iOS Photos app → «Bilder». |
| history | historik | |
| record, upload, download, reload | spela in · ladda upp · ladda ned · läs in igen | "Uploading…" → «Laddar upp…». "Downloading…" → «Laddar ned…». «Läser in…» is Loading only. |
| emoji, verification emoji | emoji · bilder | |
| link | länk | |

### 1.4 Calls

| English | sv | Notes |
|---|---|---|
| call, voice call, video call | samtal · röstsamtal · videosamtal | Button "Call" → «Ring». |
| ring, ringtone, full screen | ringa · ringsignal · helskärm | |
| incoming / missed / ongoing call | inkommande / missat / pågående samtal | "Missed call from {name}" → «Missat samtal från {name}». |
| Accept / Decline | Svara / Avvisa (calls) · Acceptera / Avvisa (invites, requests) | |
| hang up, End call | Lägg på | Both. |
| join (a call) | Anslut | |
| speaker, mute, unmute | högtalare · Stäng av ljud · Slå på ljud | "Muted" → «Ljud av». "{name} is muted" → «{name} har stängt av ljudet». |
| camera, microphone | kamera · mikrofon | |
| connection, connecting, reconnecting | anslutning · Ansluter… · Återansluter… | "Weak connection" → «Svag anslutning». "Poor connection" → «Dålig anslutningskvalitet». "Calling…" → «Ringer…». |
| picture-in-picture, minimize | bild-i-bild · Minimera | |

### 1.5 Security and encryption

| English | sv | Notes |
|---|---|---|
| encryption, encrypted, decrypt | kryptering · krypterad · dekryptera | |
| end-to-end encrypted | end-to-end-krypterad | |
| confirm (a person) | Bekräfta · bekräftelse | "Confirmed people only" → «Endast bekräftade personer». |
| approve (own device) | Godkänn · godkännande | |
| verify, verification | verifiera · verifiering | |
| security details | säkerhetsuppgifter | |
| key, room keys | nyckel · rumsnycklar | |
| backup, key backup, restore | säkerhetskopia · säkerhetskopia av nycklar · återställ | |
| security key, security phrase, recovery key | säkerhetsnyckel · säkerhetsfras · återställningsnyckel | |
| cross-signing, secret storage | korssignering · hemlig lagring | |
| session | session | |
| unlock, trust | lås upp · lita på | |
| scan, QR code, code | Skanna · QR-kod · kod | "Scan code" → «Skanna koden». |
| screenshot, screen recording, screen sharing | skärmbild · skärminspelning · skärmdelning | |
| block | Blockera / Avblockera | |
| rooted device, compromised device | rootad enhet · komprometterad enhet | |
| clipboard, password manager | urklipp · lösenordshanterare | |
| incognito keyboard | inkognitotangentbord | |
| Cryptography | kryptografi | Encryption stays «kryptering». |
| raw (security key), vouch for | rå · godkänna | |
| generate, export, import, in person | generera · exportera · importera · ansikte mot ansikte | |

### 1.6 Account, server and membership

| English | sv | Notes |
|---|---|---|
| account, password | konto · lösenord | "Wrong password." → «Fel lösenord.» "Confirm password" (the repeat field) → «Upprepa lösenordet». |
| username, display name | användarnamn · visningsnamn | |
| profile, profile photo | profil · profilbild | |
| email address | e-postadress | |
| invite | Bjud in · inbjudan | The "Invited" badge → «Inbjuden». |
| join (a room or community) | Gå med | "{target} joined" → «{target} gick med». |
| request, ask to join | förfrågan · Be om att gå med | Short "Ask" button → «Fråga». "Requested" → «Förfrågan skickad». "Let in" → «Släpp in». "Withdraw" → «Dra tillbaka». |
| leave | Lämna | "{target} left" → «{target} lämnade». |
| ban | Bannlys / Häv bannlysning · bannlysning | "Banned" heading → «Bannlysta». Never «blockera». |
| report | Rapportera · rapport | Reasons: «Trakasserier», «Olagligt innehåll», «Skräppost», «Annat skäl». |
| public / private | offentlig / privat | Agree with the noun («ett offentligt rum», «en privat gemenskap»); a label serving both is «Offentlig åtkomst» / «Privat åtkomst» / «Åtkomst via förfrågan» / «Åtkomst för gemenskapen». "Make public" → «Gör offentlig». |
| topic, description, address, ID | ämne · beskrivning · adress · ID | Room alias → «rumsadress». |
| hostname | servernamn | |
| defaults, default role | standardinställningar · standardroll | |

### 1.7 Roles and permissions

| English | sv | Notes |
|---|---|---|
| admin, moderator, owner | Administratör · Moderator · Ägare | |
| role, member, read-only, view only | roll · Medlem · Endast läsning · Endast visning | |
| permission (room or OS), access | behörighet · åtkomst | "Roles & permissions" → «Roller och behörigheter». Permission names are infinitives: "Remove people" → «Ta bort personer», "Change name" → «Ändra namn». |

### 1.8 Notifications and push

| English | sv | Notes |
|---|---|---|
| notification, test notification | notis · testnotis | Zuno's word. An OS label keeps the OS's own word («Aviseringar» on Android). |
| push, push target, push key | push · push-mål · push-nyckel | "push notifications" → «pushnotiser». |
| registration (push) | registrering · registrera | |
| delivery, background sync | leverans · bakgrundssynkronisering | "Delivery method" → «Leveransmetod». |
| battery use: Unrestricted / Optimized / Restricted | Batterianvändning: Obegränsad / Optimerad / Begränsad | Android's labels. |
| Data Saver, Autostart | Databesparing · Autostart | |
| distributor | distributör | |
| Google services / Google Play services | Google-tjänster / Google Play-tjänster | |
| Apple push | Apple-push | |
| gateway, bridge, token | gateway · brygga · token | |
| notification extension, crash | notistillägg · krasch | "Crashed" → «Kraschade». |
| diagnostics | diagnostik | |
| notification category, notification shade | notiskategori · notispanelen | |
| lock screen | låsskärm | |
| quiet, sound, vibration | tyst · ljud · vibration | "Message tone" → «Meddelandeljud». |
| standby bucket | standbygrupp | |

### 1.9 Location

| English | sv | Notes |
|---|---|---|
| location, live location | plats · liveplats | |
| share, start / stop sharing | Dela · Börja / Sluta dela | Also for sharing files. |
| approximate, maps app | ungefärlig · kartapp | |

### 1.10 Settings, storage and data

| English | sv | Notes |
|---|---|---|
| Settings | Inställningar | Zuno's, Android's and iOS's. |
| storage, data, cache | lagring · data · cache | "Clear cache" → «Rensa cache». "Data & storage" → «Data och lagring». |
| theme: Dark / Light / Follow system | Mörkt / Ljust / Följ systemet | |
| Appearance / About / Advanced, version, build | Utseende / Om / Avancerat · version · build | |
| feedback, crash reports | feedback · kraschrapporter | "Send feedback" → «Skicka feedback». |
| donate, privacy, Privacy policy, Terms | Donera · integritet · Integritetspolicy · Villkor | |
| browser, underscore | webbläsare · understreck | |
| app, home screen, shortcut, launcher | app · hemskärm · genväg · launcher | A chat app is «meddelandeapp». |
| recent apps, app switcher | senaste appar · appväxlaren | |
| Open source licenses, Source code | Licenser för öppen källkod · Källkod | |

### 1.11 Settled phrases

| English | sv | Notes |
|---|---|---|
| Asking to join (admin heading) | Förfrågningar om att gå med | "Asking to join {name}" → «Förfrågningar om att gå med i ”{name}”». |
| Ask to join (subtitle under "{name} and N others") / Asks to join | Ber om att gå med / Ber om att gå med | Both mean the people named are asking. The button stays «Be om att gå med». |
| Let them ask (setting) | Tillåt förfrågningar | |
| Joined (label on a public room or community) | Medlem | |
| N other(s) | {count} annan · {count} andra | one · other. |
| asleep (device) / suspended (app) | i viloläge / pausad | |
| Call rang / ringing | Ringde / Ringer | |
| Hidden message | dolt meddelande | Never «hemlig». |
| Secure backup (screen) | ”Återställning” | |
| Welcome to Zuno | Välkommen till Zuno | |
| With {name} / In {name} (room) / {name}'s devices | Med {name} / I rummet ”{name}” / Enheter: {name} | |
| {name} is confirmed | {name} är bekräftad | |
| character(s), check mark | tecken · bock | |
| reinstall, sign-in code, the verification check | ominstallation · inloggningskod · kontrollen | |
| "{type} event" | «Händelse: {type}» | |

### 1.12 UI actions

| English | sv |
|---|---|
| Cancel / Save / Saved | Avbryt / Spara / Sparat |
| Delete / Remove | Radera / Ta bort |
| Copy / Copied / Share | Kopiera / Kopierat / Dela |
| Send / Continue / Continue anyway | Skicka / Fortsätt / Fortsätt ändå |
| Done / Retry / Try again | Klar / Försök igen / Försök igen |
| Close / Dismiss / Open / Open settings | Stäng / Avfärda / Öppna / Öppna inställningar |
| Turn on / Turn off · On / Off | Slå på / Stäng av · På / Av |
| Allow / Not now / Skip | Tillåt / Inte nu / Hoppa över |
| Confirm / Approve | Bekräfta / Godkänn |
| Create / Start / Get started | Skapa / Starta / Kom igång |
| Edit / Change / Review | Redigera / Ändra / Granska |
| Back / Stop / Play | Tillbaka / Stoppa / Spela upp |
| Read more / Show less | Visa mer / Visa mindre |
| Mark as read / Unread | Markera som läst / Oläst |
| Refresh / Search / Start over | Uppdatera / Sök / Börja om |

### 1.13 Status words

| English | sv |
|---|---|
| Loading… / Sending… / Waiting… | Läser in… / Skickar… / Väntar… |
| Checking… / Searching… | Kontrollerar… / Söker… |
| Failed | Misslyckades |
| Not set / Unknown / None / Never | Inte angivet / Okänd / Ingen / Aldrig |
| Not available / Yes / No / Status | Inte tillgänglig / Ja / Nej / Status |
| Just now / Today / Yesterday / Coming soon | Nyss / I dag / I går / Kommer snart |

---

## 2. Swedish rules

### 2.1 Register
- «du» throughout, lowercase: «du», «dig», «din», «ditt», «dina». Never «Ni».
- Drop the possessive where Swedish does: «Kontrollera anslutningen».
- "tap" → «tryck på», "type" and "enter" → «skriv» or «ange», "choose/pick" → «välj», "pull down" → «dra nedåt», "swipe" → «svep».

### 2.2 Forms

| Where | Form | Example |
|---|---|---|
| Buttons, menu items, tooltips, actions in rows | Imperative | «Radera konto», «Spara», «Slå på högtalaren» |
| Tabs, switches and labels that name a thing | Noun | «Chattar», «Notiser», «Högtalare» |
| Body text, hints, the next step in an error | Imperative | «Tryck för att försöka igen.» |
| Titles that name something | Noun | «Rumsinställningar», «Dina enheter» |
| Titles that instruct | Imperative | «Spara din återställningskod» |
| Confirmation titles ("Delete X?") | Imperative + «?» | «Radera kontot?» |
| Progress labels | Present tense + «…» | «Skapar konto…», «Skickar…» |
| Success snack bars | Noun + participle, agreeing with the noun | «Lösenordet ändrat», «Rapporten skickad», «Meddelandet raderat» |

Statement and first-person buttons: «De matchar», «De matchar inte», «Ja, slutför», «Nej, stoppa», «Jag har redan en kod».

### 2.3 Typography
- Quotes: ”…” (U+201D on both sides), and ’…’ inside them: `”{name}”`.
- No space before «?», «!», «:» or «;».
- Apostrophe: typographic ’ only.
- Compounds are written as one word («pushnotiser», «rumsnycklar»); after an acronym, a brand or a placeholder-like English word, they take a hyphen: «QR-kod», «Google-konto», «push-mål».

### 2.4 Names
Swedish marks no gender on verbs or adjectives for people, so «{name} är bekräftad» is safe. Two things are not safe: the pronouns «han/hon», and an ending on a name («Annas enheter», where a name ending in s takes no extra s).

1. Never attach an ending to a placeholder. A possessive is recast: «Enheter: {name}», «{name} har en ny enhet».
2. Refer back with «personen» or «den här personen», never «han», «hon» or «hen».
3. English singular "they" → «personen», or drop it.

### 2.5 Fixed phrases
- Error pattern: «Meddelandet skickades inte. Kontrollera anslutningen och försök igen.»
- "Check your connection and try again." → «Kontrollera anslutningen och försök igen.»
- "Pull down to try again." → «Dra nedåt för att försöka igen.»
- "Could not X." → «Kunde inte X.» as a short label, «Det gick inte att X.» in a sentence.
- "Too many attempts." → «För många försök.» · "Something went wrong." → «Något gick fel.»
- "Nobody can undo this." → always «Ingen kan ångra detta.»
- Never «tyvärr», «förlåt», «beklagar», «framgångsrikt» or «100 % säker».

### 2.6 Numbers, dates and units
- "{date} at {time}" → «{date} kl. {time}» · "Until {time}" → «Till {time}» · "{days} days ago" → «för {days} dagar sedan» (one: «för {days} dag sedan») · "{page} of {total}" → «{page} av {total}».
- h → «tim»: «för {hours} tim sedan». min and s stay.
- Swedish plurals have two cases: `one` is exactly 1, and 0 is `other`: «0 medlemmar».

### 2.7 Ordinals
Swedish writes an ordinal as the number, a colon and «a» or «e». The recovery code has twelve words, so 1 and 2 take «:a» and the rest «:e». `securityOrdinal`: `{n, select, 1{1:a} 2{2:a} 3{3:e} other{{n}:e}}`. `settingsRecoveryWordLabel` → «{position} ordet». `settingsRecoveryConfirmBody` → «Skriv det {first} och {second} ordet från din sparade kopia.»

### 2.8 Platform labels
- Android: "Settings → Apps → Zuno → Language" → «Inställningar → Appar → Zuno → Språk».
- iOS: "Settings → General → Language & Region" → «Inställningar → Allmänt → Språk och region»; «Platstjänster», «Integritet och säkerhet», the Photos app «Bilder», and the notification settings «Varningar», «Brickor», «Bannerstil», «Kritiska varningar», «Direktmeddelanden», «Låsskärm», «Notiscenter», «Schemalagd sammanfattning», «Visa förhandsvisningar», «Ljud», «Tidskänsliga notiser», «Läs upp notiser».

---

## 3. Worked examples

| Key | English | sv |
|---|---|---|
| `settingsDeleteAccountWarningTitle` | Delete your account? | Radera ditt konto? |
| `feedbackNotSent` | Feedback not sent. Check your connection and try again. | Feedbacken skickades inte. Kontrollera anslutningen och försök igen. |
| `chatNotSentRetry` | Not sent · Tap to retry | Inte skickat · Tryck för att försöka igen |
| `callsFailureOnAnotherDevice` | You are in this call on another device. Hang up there to join here. | Du är med i samtalet på en annan enhet. Lägg på där för att ansluta här. |
| `settingsAccountPasswordChanged` | Password changed | Lösenordet ändrat |
| `blockingTitle` | Block {name}? | Blockera {name}? |
| `matrixStateNameChanged` | `{sender} changed the room name to \"{name}\"` | `{sender} ändrade rummets namn till ”{name}”` |
| `matrixStateInvited` | {sender} invited {target} | {sender} bjöd in {target} |
| `roomInfoIsConfirmed` | {name} is confirmed | {name} är bekräftad |
| `chatDeleteTitle` | `{count, plural, one{Delete message?} other{Delete {count} items?}}` | `{count, plural, one{Radera meddelandet?} other{Radera {count} objekt?}}` |
| `matrixInvitePeopleInvited` | `{count, plural, other{{count} people invited}}` | `{count, plural, one{{count} person inbjuden} other{{count} personer inbjudna}}` |
| `permissionsPhotoLibraryAddUsage` | Zuno saves photos and videos to your library only when you tap Save. | Zuno sparar bilder och videor i ditt bibliotek bara när du trycker på ”Spara”. |
