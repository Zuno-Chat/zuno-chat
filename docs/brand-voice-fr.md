# Brand voice: French (fr)

How Zuno sounds in French: the glossary and style rules behind `lib/l10n/app_fr.arb`, written for France and served to every French-speaking region. Every new English string gets its French from here. A string that needs a term this guide lacks adds the term here first.

**Binding, set by the product owner:**
- Address the reader as **vous**: «Touchez», «Saisissez», «Choisissez», «votre/vos».
- Room = **salon**, chat = **conversation**, community = **communauté**. They never overlap; «groupe» and «espace» are never used.
- **Zuno** and **Matrix** stay exactly as written, with no article: «Zuno chiffre vos messages», «la version de Zuno».

---

## 1. Glossary

Where a row has two forms, the first is the button/noun form and the second the verb used in body text (§2.2).

### 1.1 Brand-voice words

| English | fr | Notes |
|---|---|---|
| chat (one-to-one) | la conversation · les conversations | "New chat" → «Nouvelle conversation». The "Chats" tab → «Conversations». Never «discussion» or «chat». |
| room (group chat) | le salon · les salons | Never «groupe», «canal» or «salle». |
| community | la communauté | Never «espace» or «serveur». |
| "Group with {names}" | «Conversation avec {names}» | |
| device | l’appareil | Never «téléphone» or «session», even when the description says "phone". |
| recovery code | le code de récupération | The 12 words. Never «clé» or «mot de passe». |
| recovery | la récupération | "Set up recovery" → «Configurer la récupération». |
| sign in | Se connecter / se connecter · la connexion | "New sign-in" → «Nouvelle connexion». A signed-in device → «appareil connecté». |
| sign out | Se déconnecter / se déconnecter · la déconnexion | "Sign out everywhere else" → «Se déconnecter de tous les autres appareils». |
| sign up, sign-up code | Créer un compte · l’inscription · le code d’inscription | Never «enregistrement», which is push registration (§1.8). |
| server, homeserver | le serveur | |

### 1.2 People

| English | fr | Notes |
|---|---|---|
| person, people | la personne · les personnes | Grammatically feminine whatever the person's gender, so it never forces one. |
| user / member | l’utilisateur / le membre | "Unknown user" → «Utilisateur inconnu». |
| You (own name on tiles and the map) | Vous | |
| Someone / Anyone / Nobody / Everyone | Quelqu’un / N’importe qui / Personne / Tout le monde | |

### 1.3 Messaging

| English | fr | Notes |
|---|---|---|
| message | le message | Composer placeholder "Message" → «Message». |
| send | Envoyer / envoyer (envoyé) | "Not sent" → «Non envoyé». "Sending…" → «Envoi…». |
| reply | Répondre · la réponse | "Replying to {name}" → «Réponse à {name}». |
| reaction, react | la réaction · réagir | |
| edit, edited | Modifier · modifié | The "edited" marker agrees with «message». |
| delete | Supprimer / supprimer (supprimé) | "Message deleted" → «Message supprimé». Never «effacer». |
| remove (an item or person) | Retirer / retirer | Kept apart from delete. |
| seen, seen by | Vu · Vu par {people} | "Not seen yet" → «Pas encore vu». |
| typing | écrit… | "{name} is typing…" → «{name} écrit…». "Several people are typing…" → «Plusieurs personnes écrivent…». |
| mention | mentionner · la mention | "Mentions only" → «Mentions uniquement». |
| attachment, voice message | la pièce jointe · le message vocal | |
| photo / video / file | la photo / la vidéo / le fichier | |
| media, item | les médias · l’élément | The "Media" heading → «Médias». "Delete 3 items?" → «Supprimer 3 éléments ?». |
| caption, gallery | la légende · la galerie | iOS Photos app → «Photos». |
| history | l’historique | |
| record, upload, download, reload | enregistrer · envoyer · télécharger · recharger | "Uploading…" → «Envoi…». "Downloading…" → «Téléchargement…». «Chargement…» is Loading only. |
| emoji | l’emoji | The verification emoji are «images», as in the English. |

### 1.4 Calls

| English | fr | Notes |
|---|---|---|
| call, voice call, video call | l’appel · l’appel vocal · l’appel vidéo | Button "Call" → «Appeler». |
| ring, ringtone, full screen | sonner · la sonnerie · plein écran | |
| incoming / missed / ongoing call | appel entrant / manqué / en cours | "Missed call from {name}" → «Appel manqué de {name}». |
| Accept / Decline | Accepter / Refuser | Also for invites and requests. |
| hang up, End call | Raccrocher | Both. |
| join (a call) | Rejoindre / rejoindre l’appel | |
| speaker, mute, unmute | le haut-parleur · Couper le micro · Réactiver le micro | "Muted" → «Micro coupé». "{name} is muted" → «Micro de {name} coupé». |
| camera, microphone | la caméra · le micro | |
| connection, connecting, reconnecting | la connexion · Connexion… · Reconnexion… | "Weak connection" → «Connexion faible». "Calling…" → «Appel en cours…». |
| picture-in-picture, minimize | image dans l’image · Réduire | |

### 1.5 Security and encryption

| English | fr | Notes |
|---|---|---|
| encryption, encrypted, decrypt | le chiffrement · chiffré · déchiffrer | Never «cryptage», «crypter» or «décrypter». |
| end-to-end encrypted | chiffré de bout en bout | E2E stays E2E. |
| confirm (a person) | Confirmer / confirmer | Zuno's word for checking a person. "Confirmed people only" → «Personnes confirmées uniquement». |
| approve (own device) | Approuver / approuver | Only for your own devices. Never mix with confirm. |
| verify, verification | vérifier · la vérification | Only where the English says verify. |
| security details | les informations de sécurité | |
| key, room keys | la clé · les clés des salons | |
| backup, key backup, restore | la sauvegarde · la sauvegarde des clés · restaurer | |
| security key, security phrase, recovery key | la clé de sécurité · la phrase de sécurité · la clé de récupération | Advanced screens only; never the 12-word code. |
| cross-signing, secret storage | la signature croisée · le stockage secret | |
| session (Advanced only) | la session | Only where the English says "session". |
| unlock, trust | déverrouiller · faire confiance | |
| scan, QR code, code | Scanner · le code QR · le code | "Scan code" → «Scanner le code». A bare «code» is never a password. |
| screenshot, screen recording, screen sharing | la capture d’écran · l’enregistrement de l’écran · le partage d’écran | |
| block | Bloquer / débloquer | Never for ban. |
| rooted device, compromised device | appareil rooté · appareil compromis | |
| clipboard, password manager | le presse-papiers · le gestionnaire de mots de passe | |
| incognito keyboard | Clavier incognito | |

### 1.6 Account, server and membership

| English | fr | Notes |
|---|---|---|
| account, password | le compte · le mot de passe | "Wrong password." → «Mot de passe incorrect.» |
| username, display name | le nom d’utilisateur · le nom affiché | |
| profile, profile photo | le profil · la photo de profil | One term for photo, picture and avatar. |
| email address | l’adresse e-mail | |
| invite | Inviter · l’invitation | The "Invited" badge → «Invitation envoyée»: a participle would force a gender (§2.5). |
| join (a room or community) | Rejoindre / rejoindre | "{target} joined" → «{target} a rejoint». |
| request, ask to join | la demande · Demander à rejoindre | "Let in" → «Accepter». "Withdraw" → «Annuler la demande». |
| leave | Quitter / quitter | "{target} left" → «{target} a quitté». |
| remove (a person) | Retirer / retirer | The kick action. |
| ban | Bannir / lever le bannissement | "Banned" heading → «Personnes bannies». |
| report | Signaler · le signalement | Reasons: «Harcèlement», «Contenu illégal», «Spam», «Autre motif». |
| public / private | public / privé | Where one label serves both a salon (m.) and a communauté (f.), recast so nothing agrees: «Accès public», «Passer en privé». |
| topic, description, address, ID | le sujet · la description · l’adresse · l’identifiant | "Room ID" → «Identifiant du salon». |

### 1.7 Roles and permissions

| English | fr | Notes |
|---|---|---|
| admin, moderator, owner | administrateur · modérateur · propriétaire | Role badges, generic masculine. |
| role, member, read-only | le rôle · Membre · Lecture seule | |
| permission (room or OS), access | l’autorisation · l’accès | "Roles & permissions" → «Rôles et autorisations». |

### 1.8 Notifications and push

| English | fr | Notes |
|---|---|---|
| notification, test notification | la notification · la notification de test | |
| push, push target, push key | le push · la cible push · la clé push | "push notifications" → «notifications push». |
| registration (push) | l’enregistrement / enregistrer (enregistré) | Never «inscription», which is sign-up. |
| delivery, background sync | la distribution · la synchronisation en arrière-plan | "Delivery method" → «Mode de distribution». |
| battery use: Unrestricted / Optimized / Restricted | utilisation de la batterie : Sans restriction / Optimisée / Restreinte | Android's labels. |
| Data Saver, Autostart | Économiseur de données · Démarrage automatique | |
| distributor, UnifiedPush, ntfy | le distributeur · UnifiedPush · ntfy | |
| Google services / Google Play services | les services Google / les services Google Play | |
| Apple push | le push d’Apple | |
| gateway, bridge, token | la passerelle · le pont · le jeton | |
| diagnostics | le diagnostic | |
| notification category, notification shade | la catégorie de notifications · le volet des notifications | |
| lock screen | l’écran de verrouillage | |
| quiet, sound, vibration | silencieuses · le son · la vibration | "Message tone" → «Son des messages». |

### 1.9 Location

| English | fr | Notes |
|---|---|---|
| location, live location | la position · la position en direct | |
| share, start / stop sharing | Partager · Démarrer / Arrêter le partage | Also for sharing files. |
| Location Services, Privacy & Security (iOS) | Service de localisation · Confidentialité et sécurité | iOS labels. |
| approximate, maps app | approximative · l’app de cartes | |

### 1.10 Settings, storage and data

| English | fr | Notes |
|---|---|---|
| Settings | les Paramètres | Zuno's and Android's. The iOS Settings app is «Réglages» (§2.9). |
| storage, data, cache | le stockage · les données · le cache | "Clear cache" → «Vider le cache». |
| theme: Dark / Light / Follow system | Sombre / Clair / Selon le système | |
| Appearance / About / Advanced, version | Apparence / À propos / Avancé · la version | |
| feedback, crash reports | les commentaires · les rapports de plantage | "Send feedback" → «Envoyer des commentaires». |
| donate, privacy, Privacy policy, Terms | faire un don · la confidentialité · Politique de confidentialité · Conditions d’utilisation | |
| app, home screen, shortcut | l’app · l’écran d’accueil · le raccourci | «app» is feminine. |
| recent apps, app switcher | les apps récentes · le sélecteur d’apps | |
| Open source licenses, Source code | Licences open source · Code source | License names stay in English. |

### 1.11 Terms settled up front

| English | fr | Notes |
|---|---|---|
| hostname | le nom du serveur | Never left in English. |
| Asking to join (admin heading over others' requests) | Demandes d’accès | "Asking to join {name}" → «Demandes d’accès à « {name} »». |
| Ask to join (subtitle) / Asks to join | Demandent à rejoindre / Demande à rejoindre | The button stays «Demander à rejoindre». |
| Let them ask (setting) | Autoriser les demandes | Not a request the reader sends. |
| Joined (label on a public room or community) | Déjà membre | |
| N other(s) | {count} autre personne · {count} autres personnes | |
| asleep (device) / suspended (app) | en veille / suspendue | «suspendue» agrees with «l’app». |
| Call rang / ringing | L’appel a sonné / sonne | |
| Hidden message | le message masqué | «secret» reads as encrypted. |
| Secure backup (screen) | «Récupération» | A legacy name for the Recovery screen: point to it by its title. |
| Welcome to Zuno | Bienvenue dans Zuno | |
| {name} is confirmed | Vous avez confirmé {name} | A participle would agree with the person. |
| character(s) | le caractère · les caractères | |
| link | le lien | |
| build (app version) | la compilation | |
| Cryptography | la cryptographie | Encryption stays «chiffrement». |
| Room alias | l’adresse du salon | |
| View only | Consultation uniquement | Apart from «Lecture seule», the role. |
| check mark | la coche | |
| launcher | le lanceur d’applications | |
| vouch for (own devices) | valider | |
| raw (security key) | brute | |
| standby bucket | le groupe de veille | Android's raw bucket names (rare, restricted, never) stay as they are. |
| Poor connection | Mauvaise connexion | Apart from «Connexion faible». |

### 1.12 UI actions

| English | fr |
|---|---|
| Cancel / Save / Saved | Annuler / Enregistrer / Enregistré |
| Delete / Remove | Supprimer / Retirer |
| Copy / Copied / Share | Copier / Copié / Partager |
| Send / Continue / Continue anyway | Envoyer / Continuer / Continuer quand même |
| Done / Retry / Try again | Terminé / Réessayer / Réessayer |
| Close / Dismiss / Open / Open settings | Fermer / Ignorer / Ouvrir / Ouvrir les paramètres |
| Turn on / Turn off · On / Off | Activer / Désactiver · Activé / Désactivé |
| Allow / Not now / Skip | Autoriser / Plus tard / Passer |
| Confirm / Approve | Confirmer / Approuver |
| Create / Start / Get started | Créer / Démarrer / Commencer |
| Edit / Change / Review | Modifier / Changer / Examiner |
| Back / Stop / Play | Retour / Arrêter / Lire |
| Read more / Show less | Voir plus / Voir moins |
| Mark as read / Unread | Marquer comme lu / Non lus |
| Refresh / Search / Start over | Actualiser / Rechercher / Recommencer |

### 1.13 Status words

| English | fr |
|---|---|
| Loading… / Sending… / Waiting… | Chargement… / Envoi… / En attente… |
| Checking… / Searching… | Vérification… / Recherche… |
| Failed | Échec |
| Not set / Unknown / None / Never | Non défini / Inconnu / Aucun / Jamais |
| Not available / Yes / No | Indisponible / Oui / Non |
| Just now / Today / Yesterday / Coming soon | À l’instant / Aujourd’hui / Hier / Bientôt disponible |

---

## 2. Style rules

### 2.1 Register
- «vous» throughout, never «tu». Possessives «votre/vos».
- "tap" → «touchez», "type" → «saisissez» (or «tapez» for a single word), "enter" → «saisissez», "choose/pick" → «choisissez», "pull down" → «tirez vers le bas».

### 2.2 Buttons and body text

| Where | Form | Example |
|---|---|---|
| Buttons, menu items, tabs, tooltips, switches, row labels | Infinitive | «Supprimer le compte», «Enregistrer», «Activer le haut-parleur» |
| Body text, hints, the next step in an error | Imperative (vous) | «Touchez pour réessayer.» |
| Titles that name something | Noun | «Paramètres du salon», «Vos appareils» |
| Titles that instruct | Imperative | «Enregistrez votre code de récupération» |
| Confirmation titles ("Delete X?") | Infinitive + « ?» | «Supprimer votre compte ?» |
| Progress labels | Noun + «…» | «Création du compte…», «Envoi…» |
| Success snack bars | Participle, English period kept or left out | «Mot de passe modifié», «Signalement envoyé» |

Buttons that answer a question stay statements: «Elles correspondent», «Elles ne correspondent pas», «Oui, terminer», «Non, arrêter». First-person buttons stay first person: «J’ai déjà un code».

### 2.3 Case, typography and punctuation
- Sentence case everywhere, as in the English. Weekday and month names are lowercase. Never all caps.
- No exclamation marks, no emoji. Keep «…» (one character) wherever the English has it.
- **French spacing:** a no-break space (U+00A0) goes before «?», «:», «;» and «%», and inside guillemets: «Supprimer ?», «Taille : 3 Mo», «« {name} »». Never a regular space there (the line could break before the mark), and never no space. Exceptions with no space: `https://`, clock values like `{minutes}:{seconds}`, and arrows (→).
- **Apostrophe:** the typographic ’ (U+2019) everywhere: «l’appareil», «d’accès». Never the straight '.
- **Quotes:** « » with no-break spaces inside, wherever the English has quotes. The one technical value keeps straight escaped quotes: `notificationsUnknownFormat` (`\"{type}\"`). Room, topic, device names and recovery words take « »: `« {name} »`.
- When body text names a screen, row, option or button, use its exact French label in « ». «Paramètres» alone needs none.
- Keep the English «·» separators and end punctuation; colons follow the spacing rule.

### 2.4 How Zuno speaks
- Zuno never speaks as «nous» or «je». Write «Zuno…» or recast impersonally.
- «Zuno», «Android», «iOS», «Google», «Apple», no article.
- Name no other apps beyond those the English names (ntfy, Google, Apple, CarPlay).

### 2.5 Names and gender (critical)
`{name}`, `{sender}`, `{target}`, `{first}`, `{second}`, `{people}` are display names of unknown gender, and the reader's gender is unknown too.
1. Never put an article before a name.
2. Subject names go first, bare: «{name} a quitté», «{target} a rejoint».
3. Short labels with a preposition are fine: «Avec {name}», «Réponse à {name}», «Appel manqué de {name}».
4. Never use an adjective or participle that agrees with a person, the reader included: no «connecté(e)», «bloqué(e)», «invité(e)». Verbs and nouns avoid it: «Bloquer {name} ?», «Vous avez confirmé {name}», «Connexion établie». Where a noun is needed, use «la personne» or «cette personne».
5. English "they" for one person → «cette personne» or «la personne»: "once they join" → «quand cette personne aura rejoint». No inclusive-writing dots (·e).

### 2.6 Brand-voice moments

| Moment | Pattern |
|---|---|
| Error: what happened, then what to do | «Impossible d’envoyer le message. Vérifiez votre connexion et réessayez.» |
| Fixed phrases | "Check your connection and try again." → «Vérifiez votre connexion et réessayez.» · "Pull down to try again." → «Tirez vers le bas pour réessayer.» · "Too many attempts." → «Trop de tentatives.» · "Something went wrong." → «Un problème est survenu.» |
| Irreversible | "Nobody can undo this." → always «Personne ne peut annuler cette action.» |
| Reassurance | Calm present tense, no alarm words. |
| Success | Flat participle, no «avec succès». |

- Calm, plain, minimal. French runs about 20% longer than English: cut filler, never a limit, consequence or next step.
- No «Désolé», «Malheureusement», superlatives or «100 % sécurisé».

### 2.7 Numbers, dates and units
- Numbers, dates and times stay inside their placeholders; never hard-code a format.
- "{date} at {time}" → «{date} à {time}» · "Until {time}" → «Jusqu’à {time}» · "{days} days ago" → «il y a {days} jours» · "{page} of {total}" → «{page} sur {total}».
- h, min, s, km and m stay, with a no-break space before them. Bytes are octets: KB → «Ko», MB → «Mo» (`{size} Mo`). «%» takes a no-break space before it (`{percent} %`).
- Technical values stay exactly: `chat.example.org`, `https://`, `a–z, 0–9`, `@`, `ID`, `CarPlay`, `E2E`.

### 2.8 Ordinals
`securityOrdinal` precedes «mot» (masculine): `{n, select, 1{1er} 2{2e} 3{3e} other{{n}e}}`. `settingsRecoveryWordLabel` → «{position} mot». `settingsRecoveryConfirmBody` → «Saisissez le {first} et le {second} mot de votre copie enregistrée.»

### 2.9 Platform labels
- Name Android and iOS settings by that OS's French label. Android Settings is **Paramètres**; the iOS Settings app is **Réglages**: "Settings → General → Language & Region" → «Réglages → Général → Langue et région»; "Settings → Apps → Zuno → Language" → «Réglages → Apps → Zuno → Langue».
- iOS notification settings: «Écran verrouillé», «Centre de notifications», «Bannières», «Pastilles», «Sons», «Afficher les aperçus», «Résumé programmé», «Alertes critiques», «Notifications urgentes», «Annoncer les notifications».
- «iPhone» and «Android» as written. "your device" → «votre appareil», never «votre téléphone».

---

## 3. ICU and placeholder rules (the build breaks otherwise)

- Copy every `{placeholder}` exactly. Never translate, rename, add or drop one; you may move it. A string made only of placeholders and symbols keeps its placeholders and changes only for French spacing and units (`{label} : {count}`, `{size} Mo`); `{count}`, `{name} · {time}`, `CarPlay` and `UnifiedPush` stay byte-identical.
- **Plurals:** keep structure and selector name. Use only `one` and `other`. CLDR puts **0 and 1** in French `one`, so the `one` text must read right for both: always write the number as `{count}`, never «un» or «1».
  - Add a `one` case where the English has only `other` but French needs a singular: `matrixInvitePeopleInvited`, `matrixInviteWaitingForPeople`, `matrixSignupPasswordTooLong`, `securityPasswordTooShort`, `securityPasswordEmptyAdvice`, `settingsRecoveryCodeHint`, `settingsRecoveryRevealTitle`, `settingsRecoveryTooManyWords`, `roomInfoConfirmedCount`, and the `matrixRoomExitCommunityRooms*` family (both `count` and nested `orphaned`).
  - No `one` needed (same text for every number): `ageHours`, `ageMinutes`, `pushDelayHours`, `pushDelayMinutes`, `pushDelaySeconds`, `chatDeleteAllCount`, `chatSaveAll`, `chatShareAll`, `roomInfoMembersCount`, `notificationsMoreChatsAndRooms`.
  - Never add `zero`, `two`, `few`, `many` or `=n`; never use `#`. Every plural keeps `other`. Nested plurals keep their nesting.
- **Selects** (`notificationsFailureAutoSelected`, `pushSummaryPriority`, `pushSummaryStandbyBucket`, `securityOrdinal`): keep every case key; translate only the text; never drop `other`.
- **JSON:** apostrophes are literal (and typographic, §2.3). Escape `"` as `\"`. Put `\n` only where the English has it.
- **Native strings** (`x-native`): plain English stays plain; the three native plurals (`notificationsMoreChats`, `notificationsMoreRooms`, `notificationsMoreChatsAndRooms`) stay whole-message plurals. The five `x-ios-infoplist` keys have no placeholders and start with «Zuno…». Notification strings are the shortest text: keep them short.
- `languageNativeName` → «Français».

---

## 4. Worked examples

| Key | English | fr |
|---|---|---|
| `settingsDeleteAccountWarningTitle` | Delete your account? | Supprimer votre compte ? |
| `feedbackNotSent` | Feedback not sent. Check your connection and try again. | Commentaires non envoyés. Vérifiez votre connexion et réessayez. |
| `chatNotSentRetry` | Not sent · Tap to retry | Non envoyé · Touchez pour réessayer |
| `callsFailureOnAnotherDevice` | You are in this call on another device. Hang up there to join here. | Vous êtes déjà dans cet appel sur un autre appareil. Raccrochez-y pour le rejoindre ici. |
| `settingsAccountPasswordChanged` | Password changed | Mot de passe modifié |
| `blockingTitle` | Block {name}? | Bloquer {name} ? |
| `matrixStateNameChanged` | `{sender} changed the room name to \"{name}\"` | `{sender} a renommé le salon en « {name} »` |
| `chatDeleteTitle` | `{count, plural, one{Delete message?} other{Delete {count} items?}}` | `{count, plural, one{Supprimer le message ?} other{Supprimer {count} éléments ?}}` |
| `matrixInvitePeopleInvited` | `{count, plural, other{{count} people invited}}` | `{count, plural, one{{count} personne invitée} other{{count} personnes invitées}}` |
| `permissionsPhotoLibraryAddUsage` | Zuno saves photos and videos to your library only when you tap Save. | Zuno enregistre des photos et des vidéos dans votre photothèque uniquement quand vous touchez « Enregistrer ». |

In this file a space before «?», «:», «%» or inside « » stands for the no-break space U+00A0.
