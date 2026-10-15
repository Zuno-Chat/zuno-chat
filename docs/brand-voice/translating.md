# Translating Zuno

Every translation follows this file and its own guide in this folder. This file holds what all languages share; a language guide holds only what is specific to it: its binding choices, its glossary, and its own grammar and typography. The voice itself is `README.md`.

| Guide | Translation file | Register | chat / room / community |
|---|---|---|---|
| `el.md` | `app_el.arb` | formal plural (εσείς) | συνομιλία / αίθουσα / κοινότητα |
| `pt-BR.md` | `app_pt.arb` (base, Brazil) | você | conversa / sala / comunidade |
| `pt-PT.md` | `app_pt_PT.arb` | formal third person | conversa / sala / comunidade |
| `fr.md` | `app_fr.arb` | vous | conversation / salon / communauté |
| `es.md` | `app_es.arb` | tú | chat / sala / comunidad |
| `it.md` | `app_it.arb` | tu | chat / stanza / comunità |
| `de.md` | `app_de.arb` | du | Chat / Raum / Community |
| `pl.md` | `app_pl.arb` | ty («Twój» capitalized) | czat / pokój / społeczność |
| `sq.md` | `app_sq.arb` | ti | bisedë / dhomë / komunitet |

## How a guide works

- The binding choices at the top of a guide (register, the words for chat, room and community, how Zuno takes an article) are set by the product owner. They change only on the product owner's say.
- Every new English string gets its translation from the guide. A string that needs a term the guide lacks adds the term to the guide first.
- Every guide has the same parts: binding choices, the glossary (§1), the language's rules (§2: register, the forms table, typography, names, fixed phrases, numbers, ordinals, platform labels) and worked examples (§3). A new language copies that shape.
- Where a glossary row has two forms, the first is the button/noun form and the second the verb used in body text (§2.2).

## Meaning every language keeps

A guide's glossary gives the words; these rules say how they are used.

- Chat, room and community never overlap, and no language uses its word for "group".
- Device is never a word for phone, mobile or session, even when an English description says "phone": "your device", never "your phone".
- The recovery code is the 12 words, never a key or a password. Security key, security phrase and recovery key appear on the Advanced screens only and never name the 12-word code.
- Sign-up and push registration are different things. Where a language has one word for both, context keeps them apart.
- Confirm is for people and approve is for your own devices; they never mix. Verify appears only where the English says verify, session only where the English says session.
- Delete and remove stay distinct. Block is never used for ban.
- A bare "code" always means a code, never a password; the password is always written in full.
- Profile photo, picture and avatar are one term.
- "Secure backup" is a legacy name for the Recovery screen: point to it by that screen's title.
- "Asking to join" is an admin heading over other people's requests, never the reader asking. "Let them ask" is a setting, not a request the reader sends.
- A device asleep and an app suspended stay apart, as do "Weak connection" and "Poor connection", and "View only" (a screen state) and "Read-only" (the role).
- A hidden message is never "secret", which reads as encrypted.
- The hostname is never left in English.
- The verification emoji are "pictures", as in the English.
- Settings covers both Zuno's settings and the phone's.
- Android's raw standby bucket names (rare, restricted, never) stay as they are.
- Zuno, Matrix, UnifiedPush, ntfy, CarPlay, iPhone and Android stay exactly as written. License names stay in English.

## Style every language keeps

- Sentence case, as in the English. Never all caps.
- No exclamation marks and no emoji. «…» is one character wherever the English has it.
- Wherever the English has quotes, use the language's own quotes (its guide says which). The one technical value, `notificationsUnknownFormat`, keeps straight escaped quotes (`\"{type}\"`). Room, topic and device names and recovery words are quoted.
- When body text names a screen, row, option or button, it uses that item's exact translated label, quoted. Settings alone needs no quotes. An OS setting name matches what Android or iOS shows in that language.
- Keep the English «·» separators and end punctuation exactly. Colons follow the language's spacing.
- Buttons and labels, body text, titles, confirmation titles, progress labels and success messages each take one fixed form per language (the guide's forms table). Buttons that answer a question stay statements; first-person buttons stay first person.
- Zuno never speaks as "we" or "I": write "Zuno…" or recast impersonally. Name no other apps beyond those the English names.

### Names and gender

`{name}`, `{sender}`, `{target}`, `{first}`, `{second}` and `{people}` are display names of unknown gender, and the reader's gender is unknown too.

1. Never put an article before a name, and never decline it.
2. A subject name goes first, bare.
3. Short labels with a preposition and the bare name are fine: "With {name}", "Replying to {name}", "Missed call from {name}".
4. Never an adjective or participle that agrees with a person, the reader included. Use a verb or a noun ("the person"), or recast.
5. English singular "they" becomes "the person" or "this person", or drops out.
6. No inclusive-writing symbols (·e, *, :, @, ə).

### Brand-voice moments

The moments in `README.md` apply in every language.

- Errors say what happened, then what to do. No apology words, no "unfortunately", no superlatives, no "100% secure".
- Success is a flat participle, never "successfully".
- Reassurance is calm present tense with no alarm words.
- Each guide fixes, in its own words, "Check your connection and try again.", "Pull down to try again.", "Too many attempts.", "Something went wrong." and the irreversible line "Nobody can undo this.", which is always worded the same.
- Calm and minimal: cut filler, never a limit, a consequence or a next step. Translations run 20 to 30% longer than English, and the layout tests run every language on the smallest phone with large text.

### Numbers and units

- Numbers, dates and times stay inside their placeholders; never hard-code a format. Numerals already in the English text stay numerals.
- Units (h, min, s, km, m, B, KB, MB) and «%» stay as written, spacing included, unless the guide says otherwise.
- Technical values stay exactly: `chat.example.org`, `https://`, `a–z, 0–9`, `@`, `ID`, `CarPlay`, `E2E`.

## ICU and placeholders (the build breaks otherwise)

- Copy every `{placeholder}` exactly; never translate, rename, add or drop one. You may move it.
- A string made only of placeholders and symbols stays byte-identical, unless the language's guide changes its spacing or units: `{count}`, `{name} · {time}`, `{label}: {count}`, `{size} MB`, `CarPlay`, `UnifiedPush`.
- **Plurals** keep their structure and selector name. Use only `one` and `other`, except in Polish, which adds `few` and `many` (its guide says how); every plural keeps `other`; nested plurals keep their nesting. Never add `zero`, `two` or `=n`, and never use `#`: write the number as `{count}` (or the selector's own name), never as a word.
  - Where a language puts 0 in `one` (Brazilian Portuguese and French), the `one` text must read right for both 0 and 1.
  - Add a `one` case (in Polish, `one`, `few` and `many`) where the English has only `other` but the language needs a singular: `matrixInvitePeopleInvited`, `matrixInviteWaitingForPeople`, `matrixSignupPasswordTooLong`, `securityPasswordTooShort`, `securityPasswordEmptyAdvice`, `settingsRecoveryCodeHint`, `settingsRecoveryRevealTitle`, `settingsRecoveryTooManyWords`, `roomInfoConfirmedCount`, and the `matrixRoomExitCommunityRooms*` family (both `count` and the nested `orphaned`).
  - No `one` is needed where the text is the same for every number: `ageHours`, `ageMinutes`, `pushDelayHours`, `pushDelayMinutes`, `pushDelaySeconds`, `chatDeleteAllCount`, `chatSaveAll`, `chatShareAll`, `roomInfoMembersCount`, `notificationsMoreChatsAndRooms`.
- **Selects** (`notificationsFailureAutoSelected`, `pushSummaryPriority`, `pushSummaryStandbyBucket`, `securityOrdinal`) keep every case key; translate only the text and never drop `other`. `securityOrdinal` and `settingsRecoveryWordLabel` follow the guide's ordinal rule.
- **JSON:** apostrophes are literal (ICU escaping is off). Escape `"` as `\"`. Put `\n` only where the English has it. A translation file holds only `"key": "value"` pairs, in the English key order.
- **Native strings** (`x-native`, `x-ios-infoplist`): a plain English string stays plain text. The three native plurals (`notificationsMoreChats`, `notificationsMoreRooms`, `notificationsMoreChatsAndRooms`) stay single plurals covering the whole message. The five `permissions*Usage` keys have no placeholders and start with "Zuno…" in the language's own form. Notification strings are the shortest text: keep them short.
- `languageNativeName` is the language's own name, as its guide gives it.
