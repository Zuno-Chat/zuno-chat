# Brand voice: Polish (pl)

Polish for `lib/l10n/app_pl.arb`, written for Poland. The rules all languages share are in `translating.md`; this guide holds only what is Polish.

**Binding, set by the product owner:**
- Address the reader as **ty**, and capitalize every form of ty and twój in direct address: «Wpisz kod», «Twoje wiadomości», «zaprasza Cię».
- Chat = **czat**, room = **pokój**, community = **społeczność**. Never «grupa», «kanał», «przestrzeń» or «rozmowa» for any of them.
- **Zuno**, **Google** and **Apple** never decline: «w Zuno», «konto Google». **Matrix**, **Android** and **iOS** follow a noun so they need not decline either: «w sieci Matrix», «w systemie Android».
- `languageNativeName` → «Polski».

---

## 1. Glossary

### 1.1 Brand-voice words

| English | pl | Notes |
|---|---|---|
| chat (one-to-one) | czat · czaty | "New chat" → «Nowy czat». The "Chats" tab → «Czaty». |
| room (group chat) | pokój · pokoje (gen. pl. pokoi) | "New room" → «Nowy pokój». |
| community | społeczność · społeczności | "New community" → «Nowa społeczność». |
| "Group with {names}" | «Czat: {names}» | |
| device | urządzenie | Never «telefon» or «komórka». |
| recovery code | kod odzyskiwania | Never «klucz» or «hasło». |
| recovery | odzyskiwanie | "Set up recovery" → «Skonfiguruj odzyskiwanie». |
| sign in | Zaloguj się · logowanie | "New sign-in" → «Nowe logowanie». A signed-in device → «zalogowane urządzenie». |
| sign out | Wyloguj się · wylogowanie | "Sign out everywhere else" → «Wyloguj na pozostałych urządzeniach». |
| sign up, sign-up code | Utwórz konto · rejestracja · kod rejestracyjny | Push registration is «rejestracja push». |
| server, homeserver | serwer | |

### 1.2 People

| English | pl | Notes |
|---|---|---|
| person, people | osoba · osoby · osób | Grammatically feminine, so it forces no gender on the person: «ta osoba», «tej osoby», «tę osobę». |
| user / member | osoba / członek | "Unknown user" → «Nieznana osoba». Never «użytkownik» about a person; «nazwa użytkownika» (the field) is fine. |
| You (own name on tiles and the map) | Ty | |
| Someone / Anyone / Nobody / Everyone | Ktoś / Każdy / Nikt / Wszyscy | "Anyone can join" → «Każdy może dołączyć». |

### 1.3 Messaging

| English | pl | Notes |
|---|---|---|
| message | wiadomość | Composer placeholder "Message" → «Wiadomość». |
| send | Wyślij · wysyłanie | "Not sent" → «Nie wysłano». "Sending…" → «Wysyłanie…». |
| reply | Odpowiedz · odpowiedź | "Replying to {name}" → «Odpowiadasz: {name}». |
| reaction, react | reakcja · zareaguj | |
| edit, edited | Edytuj · edytowano | |
| delete | Usuń · usunięcie | "Message deleted" → «Wiadomość usunięta». |
| remove (an item) | Usuń | Polish has one everyday verb for deleting and removing an item; the object keeps them apart. |
| remove (a person) | Wyrzuć · wyrzucenie | The kick action. A person is never «usunięty». "Remove from room" → «Wyrzuć z pokoju». |
| seen, seen by | Wyświetlone · Wyświetlone przez: {people} | "Not seen yet" → «Jeszcze niewyświetlone». |
| typing | pisze… | "{name} is typing…" → «{name} pisze…». "Several people are typing…" → «Kilka osób pisze…». |
| mention | wspomnij · wzmianka | "Mentions only" → «Tylko wzmianki». |
| attachment, voice message | załącznik · wiadomość głosowa | |
| photo / video / file | zdjęcie / film / plik | |
| media, item | multimedia · element | The "Media" heading → «Multimedia». "Delete 3 items?" → «Usunąć 3 elementy?». |
| caption, gallery | podpis · galeria | iOS Photos app → «Zdjęcia». |
| history | historia | |
| record, upload, download, reload | nagraj · prześlij · pobierz · wczytaj ponownie | "Uploading…" → «Przesyłanie…». "Downloading…" → «Pobieranie…». «Ładowanie…» is Loading only. |
| emoji, verification emoji | emoji · obrazki | |

### 1.4 Calls

| English | pl | Notes |
|---|---|---|
| call, voice call, video call | połączenie · połączenie głosowe · połączenie wideo | Button "Call" → «Zadzwoń». |
| ring, ringtone, full screen | dzwonić · dzwonek · pełny ekran | |
| incoming / missed / ongoing call | połączenie przychodzące / nieodebrane / trwające | "Missed call from {name}" → «Nieodebrane połączenie: {name}». |
| Accept / Decline | Odbierz / Odrzuć (calls) · Przyjmij / Odrzuć (invites, requests) | |
| hang up, End call | Rozłącz | Both. |
| join (a call) | Dołącz | |
| speaker, mute, unmute | głośnik · Wycisz · Wyłącz wyciszenie | "Muted" → «Wyciszono». "{name} is muted" → «{name} ma wyciszony mikrofon». |
| camera, microphone | kamera · mikrofon | |
| connection, connecting, reconnecting | połączenie · Łączenie… · Ponowne łączenie… | "Weak connection" → «Słabe połączenie». "Poor connection" → «Niska jakość połączenia». "Calling…" → «Dzwonienie…». |
| picture-in-picture, minimize | obraz w obrazie · Minimalizuj | |

### 1.5 Security and encryption

| English | pl | Notes |
|---|---|---|
| encryption, encrypted, decrypt | szyfrowanie · zaszyfrowane · odszyfruj | |
| end-to-end encrypted | szyfrowane end-to-end | |
| confirm (a person) | Potwierdź · potwierdzenie | "Confirmed people only" → «Tylko potwierdzone osoby». |
| approve (own device) | Zatwierdź · zatwierdzenie | |
| verify, verification | zweryfikuj · weryfikacja | |
| security details | dane bezpieczeństwa | |
| key, room keys | klucz · klucze pokoju | |
| backup, key backup, restore | kopia zapasowa · kopia zapasowa kluczy · przywróć | |
| security key, security phrase, recovery key | klucz bezpieczeństwa · fraza bezpieczeństwa · klucz odzyskiwania | |
| cross-signing, secret storage | podpisywanie krzyżowe · tajny magazyn | |
| session | sesja | |
| unlock, trust | odblokuj · ufać | |
| scan, QR code, code | Zeskanuj · kod QR · kod | "Scan code" → «Zeskanuj kod». |
| screenshot, screen recording, screen sharing | zrzut ekranu · nagrywanie ekranu · udostępnianie ekranu | |
| block | Zablokuj / Odblokuj | |
| rooted device, compromised device | urządzenie z rootem · przejęte urządzenie | |
| clipboard, password manager | schowek · menedżer haseł | |
| incognito keyboard | klawiatura incognito | |
| Cryptography | kryptografia | Encryption stays «szyfrowanie». |
| raw (security key), vouch for | nieformatowany · zatwierdź | |

### 1.6 Account, server and membership

| English | pl | Notes |
|---|---|---|
| account, password | konto · hasło | "Wrong password." → «Nieprawidłowe hasło.» "Confirm password" (the repeat field) → «Powtórz hasło». |
| username, display name | nazwa użytkownika · nazwa wyświetlana | |
| profile, profile photo | profil · zdjęcie profilowe | |
| email address | adres e-mail | |
| invite | Zaproś · zaproszenie | The "Invited" badge → «Zaproszono». |
| join (a room or community) | Dołącz · dołączyć | "{target} joined" → «{target} dołącza». |
| request, ask to join | prośba · Poproś o dołączenie | "Let in" → «Wpuść». "Withdraw" → «Wycofaj prośbę». |
| leave | Opuść · opuścić | "{target} left" → «{target} wychodzi». |
| ban | Zbanuj / Odbanuj · zbanowanie | "Banned" heading → «Zbanowane osoby». Never «zablokuj». |
| report | Zgłoś · zgłoszenie | Reasons: «Nękanie», «Nielegalne treści», «Spam», «Inny powód». |
| public / private | publiczny / prywatny | Agree with the noun described; a label serving both rooms and communities is «Dostęp publiczny» / «Dostęp prywatny». "Make public" → «Ustaw dostęp publiczny». |
| topic, description, address, ID | temat · opis · adres · ID | Room alias → «adres pokoju». |
| hostname | nazwa serwera | |

### 1.7 Roles and permissions

| English | pl | Notes |
|---|---|---|
| admin, moderator, owner | Administrator · Moderator · Właściciel | Role badges only, never about a named person in a sentence. |
| role, member, read-only, view only | rola · Członek · Tylko odczyt · Tylko podgląd | |
| permission (room or OS), access | uprawnienie · dostęp | "Roles & permissions" → «Role i uprawnienia». Permission names are verbal nouns: "Remove people" → «Wyrzucanie osób», "Change name" → «Zmiana nazwy». |

### 1.8 Notifications and push

| English | pl | Notes |
|---|---|---|
| notification, test notification | powiadomienie · powiadomienie testowe | |
| push, push target, push key | push · cel push · klucz push | "push notifications" → «powiadomienia push». |
| registration (push) | rejestracja · zarejestruj | |
| delivery, background sync | dostarczanie · synchronizacja w tle | "Delivery method" → «Sposób dostarczania». |
| battery use: Unrestricted / Optimized / Restricted | Wykorzystanie baterii: Bez ograniczeń / Zoptymalizowane / Z ograniczeniami | Android's labels. |
| Data Saver, Autostart | Oszczędzanie danych · Autostart | |
| distributor | dystrybutor | |
| Google services / Google Play services | usługi Google / Usługi Google Play | |
| Apple push | push Apple | |
| gateway, bridge, token | bramka · mostek · token | |
| diagnostics | diagnostyka | |
| notification category, notification shade | kategoria powiadomień · obszar powiadomień | |
| lock screen | ekran blokady | |
| quiet, sound, vibration | bez dźwięku · dźwięk · wibracje | "Message tone" → «Dźwięk wiadomości». |
| standby bucket | zasobnik gotowości | |

### 1.9 Location

| English | pl | Notes |
|---|---|---|
| location, live location | lokalizacja · lokalizacja na żywo | |
| share, start / stop sharing | Udostępnij · Zacznij / Przestań udostępniać | Also for sharing files. |
| approximate, maps app | przybliżona · aplikacja z mapami | |

### 1.10 Settings, storage and data

| English | pl | Notes |
|---|---|---|
| Settings | Ustawienia | Zuno's, Android's and iOS's. |
| storage, data, cache | pamięć · dane · pamięć podręczna | "Clear cache" → «Wyczyść pamięć podręczną». |
| theme: Dark / Light / Follow system | Ciemny / Jasny / Jak w systemie | |
| Appearance / About / Advanced, version, build | Wygląd / Informacje / Zaawansowane · wersja · kompilacja | |
| feedback, crash reports | opinia · raporty o awariach | "Send feedback" → «Wyślij opinię». |
| donate, privacy, Privacy policy, Terms | Wesprzyj · prywatność · Polityka prywatności · Warunki korzystania | |
| app, home screen, shortcut, launcher | aplikacja · ekran główny · skrót · launcher | A chat app is «komunikator». |
| recent apps, app switcher | ostatnie aplikacje · przełącznik aplikacji | |
| Open source licenses, Source code | Licencje open source · Kod źródłowy | |

### 1.11 Settled phrases

| English | pl | Notes |
|---|---|---|
| Asking to join (admin heading) | Prośby o dołączenie | "Asking to join {name}" → «Prośby o dołączenie: „{name}”». |
| Ask to join (subtitle) / Asks to join | Proszą o dołączenie / Prosi o dołączenie | The button stays «Poproś o dołączenie». |
| Let them ask (setting) | Zezwalaj na prośby | |
| Joined (label on a public room or community) | Dołączono | |
| N other(s) | {count} inna osoba · {count} inne osoby · {count} innych osób | one · few · many. |
| asleep (device) / suspended (app) | uśpione / wstrzymana | They agree with «urządzenie» and «aplikacja». |
| Call rang / ringing | Dzwoniono / Dzwoni | |
| Hidden message | ukryta wiadomość | Never «tajna». |
| Secure backup (screen) | „Odzyskiwanie” | |
| Welcome to Zuno | Witaj w Zuno | |
| With {name} / In {name} (room) / {name}'s devices | Czat: {name} / W pokoju „{name}” / urządzenia konta: {name} | |
| {name} is confirmed | {name} ma potwierdzoną tożsamość | The participle agrees with «tożsamość», not the person (§2.4). |
| character(s), link, check mark | znak · link · znacznik wyboru | |

### 1.12 UI actions

| English | pl |
|---|---|
| Cancel / Save / Saved | Anuluj / Zapisz / Zapisano |
| Delete / Remove (item) / Remove (person) | Usuń / Usuń / Wyrzuć |
| Copy / Copied / Share | Kopiuj / Skopiowano / Udostępnij |
| Send / Continue / Continue anyway | Wyślij / Dalej / Kontynuuj mimo to |
| Done / Retry / Try again | Gotowe / Ponów / Spróbuj ponownie |
| Close / Dismiss / Open / Open settings | Zamknij / Ukryj / Otwórz / Otwórz ustawienia |
| Turn on / Turn off · On / Off | Włącz / Wyłącz · Wł. / Wył. |
| Allow / Not now / Skip | Zezwól / Nie teraz / Pomiń |
| Confirm / Approve | Potwierdź / Zatwierdź |
| Create / Start / Get started | Utwórz / Rozpocznij / Zacznij |
| Edit / Change / Review | Edytuj / Zmień / Przejrzyj |
| Back / Stop / Play | Wstecz / Zatrzymaj / Odtwórz |
| Read more / Show less | Pokaż więcej / Pokaż mniej |
| Mark as read / Unread | Oznacz jako przeczytane / Nieprzeczytane |
| Refresh / Search / Start over | Odśwież / Szukaj / Zacznij od nowa |

### 1.13 Status words

| English | pl |
|---|---|
| Loading… / Sending… / Waiting… | Ładowanie… / Wysyłanie… / Oczekiwanie… |
| Checking… / Searching… | Sprawdzanie… / Wyszukiwanie… |
| Failed | Nie udało się |
| Not set / Unknown / None / Never | Nie ustawiono / Nieznane / Brak / Nigdy |
| Not available / Yes / No / Status | Niedostępne / Tak / Nie / Stan |
| Just now / Today / Yesterday / Coming soon | Przed chwilą / Dzisiaj / Wczoraj / Wkrótce |

---

## 2. Polish rules

### 2.1 Register
- «ty» throughout, and every form of ty and twój in direct address is capitalized: «Ty», «Ciebie», «Cię», «Tobie», «Ci», «Twój», «Twoja», «Twoje», «Twoich». The reflexive «swój» stays lowercase.
- Drop the possessive where Polish does: «Sprawdź połączenie», not «Sprawdź Twoje połączenie».
- "tap" → «dotknij», "type" and "enter" → «wpisz», "choose/pick" → «wybierz», "pull down" → «przeciągnij w dół».

### 2.2 Forms

| Where | Form | Example |
|---|---|---|
| Buttons, menu items, tooltips, actions in rows | Imperative (ty) | «Usuń konto», «Zapisz», «Włącz głośnik» |
| Tabs, switches and labels that name a thing | Noun | «Czaty», «Powiadomienia», «Głośnik» |
| Body text, hints, the next step in an error | Imperative (ty) | «Dotknij, aby spróbować ponownie.» |
| Titles that name something | Noun | «Ustawienia pokoju», «Twoje urządzenia» |
| Titles that instruct | Imperative | «Zapisz swój kod odzyskiwania» |
| Confirmation titles ("Delete X?") | Infinitive + «?» | «Usunąć konto?» |
| Progress labels | Verbal noun + «…» | «Tworzenie konta…», «Wysyłanie…» |
| Success snack bars | Impersonal «-no/-to» | «Zmieniono hasło», «Wysłano zgłoszenie» |

Statement and first-person buttons: «Pasują», «Nie pasują», «Tak, zakończ», «Nie, przerwij», «Mam już kod».

### 2.3 Typography
- Quotes: „…” (U+201E, U+201D): `„{name}”`.
- No space before «?», «!», «:», «;» or «%».
- Apostrophe: Polish rarely needs one; never the straight '.
- Compounds with English words stay apart or hyphenated as Polish writes them: «adres e-mail», «kod QR», «powiadomienia push».
- Colons stay exactly as in the English, plus the name colons of §2.4.

### 2.4 Names
Polish marks gender in the past tense («wysłał/wysłała») and in predicate adjectives and participles («jest potwierdzony/potwierdzona»), and a name changes form after a preposition or as an object («z Anną»). None of these is safe for a name or for the reader.

1. A name stays in the nominative: as the subject («{name} pisze…») or after a colon («Nieodebrane połączenie: {name}», «Odpowiadasz: {name}», «Zablokować: {name}?»). Never after a preposition, as an object or as a possessive.
2. What a named person does takes the present tense, and every timeline event does: «{sender} zmienia nazwę pokoju na „{name}”», «{target} dołącza», «{target} wychodzi». A second name goes after a colon: «{sender} zaprasza: {target}», «{sender} wyrzuca z pokoju: {target}».
3. A state takes «ma» or «jest» with words that agree with a thing: «{name} ma potwierdzoną tożsamość», «{name} ma wyciszony mikrofon», «{name} ma nowe dane bezpieczeństwa».
4. The reader takes the present («Nie jesteś już w tym pokoju»), «masz» («Masz nowe urządzenie») or the impersonal «-no/-to» form («Zalogowano», «Usunięto Cię z pokoju»). Never «wysłałeś», «jesteś zalogowany» or similar.
5. Once the name has appeared, refer back with «ta osoba», «tej osoby» or «tę osobę»: "Scan {name}'s code" → «Zeskanuj kod: {name}», and later «kod tej osoby».
6. English singular "they" → «ta osoba», or drop it.
7. Never a doublet such as «(a)», «/a» or «-a».

### 2.5 Fixed phrases
- Error pattern: «Nie udało się wysłać wiadomości. Sprawdź połączenie i spróbuj ponownie.»
- "Check your connection and try again." → «Sprawdź połączenie i spróbuj ponownie.»
- "Pull down to try again." → «Przeciągnij w dół, aby spróbować ponownie.»
- "Too many attempts." → «Zbyt wiele prób.» · "Something went wrong." → «Coś poszło nie tak.»
- "Nobody can undo this." → always «Nikt nie może tego cofnąć.»
- Never «Niestety», «Przepraszamy», «pomyślnie» or «w 100% bezpieczne».

### 2.6 Numbers, dates and units
- "{date} at {time}" → «{date} o {time}» · "Until {time}" → «Do {time}» · "{days} days ago" → «{days} dni temu» (one: «{days} dzień temu») · "{page} of {total}" → «{page} z {total}».
- h → «godz.»: «{hours} godz. temu».
- Polish plurals have four cases. `one` is exactly 1; `few` is 2–4, 22–24, 32–34 and so on, but not 12–14; `many` is 0, 5–21, 25–31 and so on; `other` covers only fractions and repeats the `many` text.
- Every plural whose text changes with the number has all four cases, including those `translating.md` lists for an added `one`: `{count, plural, one{{count} osoba} few{{count} osoby} many{{count} osób} other{{count} osób}}`. 0 is `many`: «0 członków».

### 2.7 Ordinals
`securityOrdinal` precedes «słowo»: `{n, select, 1{1.} 2{2.} 3{3.} other{{n}.}}`. `settingsRecoveryWordLabel` → «{position} słowo». `settingsRecoveryConfirmBody` → «Wpisz {first} i {second} słowo z zapisanej kopii.»

### 2.8 Platform labels
- Android and iOS both call Settings **Ustawienia**: "Settings → General → Language & Region" → «Ustawienia → Ogólne → Język i region»; "Settings → Apps → Zuno → Language" → «Ustawienia → Aplikacje → Zuno → Język».
- iOS: «Usługi lokalizacji», «Prywatność i ochrona», «Ekran blokady», «Centrum powiadomień», «Banery», «Plakietki», «Dźwięki», «Pokazuj podglądy», «Zaplanowane podsumowanie», «Alerty krytyczne», «Powiadomienia pilne», «Zapowiadaj powiadomienia».

---

## 3. Worked examples

| Key | English | pl |
|---|---|---|
| `settingsDeleteAccountWarningTitle` | Delete your account? | Usunąć konto? |
| `feedbackNotSent` | Feedback not sent. Check your connection and try again. | Nie wysłano opinii. Sprawdź połączenie i spróbuj ponownie. |
| `chatNotSentRetry` | Not sent · Tap to retry | Nie wysłano · Dotknij, aby ponowić |
| `callsFailureOnAnotherDevice` | You are in this call on another device. Hang up there to join here. | Uczestniczysz w tym połączeniu na innym urządzeniu. Rozłącz się tam, aby dołączyć tutaj. |
| `settingsAccountPasswordChanged` | Password changed | Zmieniono hasło |
| `blockingTitle` | Block {name}? | Zablokować: {name}? |
| `matrixStateNameChanged` | `{sender} changed the room name to \"{name}\"` | `{sender} zmienia nazwę pokoju na „{name}”` |
| `matrixStateInvited` | {sender} invited {target} | {sender} zaprasza: {target} |
| `roomInfoIsConfirmed` | {name} is confirmed | {name} ma potwierdzoną tożsamość |
| `chatDeleteTitle` | `{count, plural, one{Delete message?} other{Delete {count} items?}}` | `{count, plural, one{Usunąć wiadomość?} few{Usunąć {count} elementy?} many{Usunąć {count} elementów?} other{Usunąć {count} elementów?}}` |
| `matrixInvitePeopleInvited` | `{count, plural, other{{count} people invited}}` | `{count, plural, one{Zaproszono {count} osobę} few{Zaproszono {count} osoby} many{Zaproszono {count} osób} other{Zaproszono {count} osób}}` |
| `permissionsPhotoLibraryAddUsage` | Zuno saves photos and videos to your library only when you tap Save. | Zuno zapisuje zdjęcia i filmy w Twojej bibliotece tylko wtedy, gdy dotkniesz „Zapisz”. |
