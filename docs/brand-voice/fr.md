# Brand voice: French (fr)

French for `lib/l10n/app_fr.arb`, written for France and served to every French-speaking region. The rules all languages share are in `translating.md`; this guide holds only what is French.

**Binding, set by the product owner:**
- Address the reader as **vous**: «Touchez», «Saisissez», «Choisissez», «votre/vos».
- Chat = **conversation**, room = **salon**, community = **communauté**. Never «groupe», «espace», «discussion» or «salle».
- **Zuno**, **Google** and **Apple** take no article: «Zuno chiffre vos messages», «la version de Zuno».
- `languageNativeName` → «Français».

---

## 1. Glossary

### 1.1 Brand-voice words

| English | fr | Notes |
|---|---|---|
| chat (one-to-one) | la conversation · les conversations | "New chat" → «Nouvelle conversation». The "Chats" tab → «Conversations». |
| room (group chat) | le salon · les salons | Never «canal». |
| community | la communauté | Never «serveur». |
| "Group with {names}" | «Conversation avec {names}» | |
| device | l’appareil | Never «téléphone». |
| recovery code | le code de récupération | Never «clé» or «mot de passe». |
| recovery | la récupération | "Set up recovery" → «Configurer la récupération». |
| sign in | Se connecter / se connecter · la connexion | "New sign-in" → «Nouvelle connexion». A signed-in device → «appareil connecté». |
| sign out | Se déconnecter / se déconnecter · la déconnexion | "Sign out everywhere else" → «Se déconnecter de tous les autres appareils». |
| sign up, sign-up code | Créer un compte · l’inscription · le code d’inscription | Never «enregistrement», which is push registration. |
| server, homeserver | le serveur | |

### 1.2 People

| English | fr | Notes |
|---|---|---|
| person, people | la personne · les personnes | Grammatically feminine, so it forces no gender. |
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
| remove (an item or person) | Retirer / retirer | |
| seen, seen by | Vu · Vu par {people} | "Not seen yet" → «Pas encore vu». |
| typing | écrit… | "{name} is typing…" → «{name} écrit…». "Several people are typing…" → «Plusieurs personnes écrivent…». |
| mention | mentionner · la mention | "Mentions only" → «Mentions uniquement». |
| attachment, voice message | la pièce jointe · le message vocal | |
| photo / video / file | la photo / la vidéo / le fichier | |
| media, item | les médias · l’élément | The "Media" heading → «Médias». "Delete 3 items?" → «Supprimer 3 éléments ?». |
| caption, gallery | la légende · la galerie | iOS Photos app → «Photos». |
| history | l’historique | |
| record, upload, download, reload | enregistrer · envoyer · télécharger · recharger | "Uploading…" → «Envoi…». "Downloading…" → «Téléchargement…». «Chargement…» is Loading only. |
| emoji, verification emoji | l’emoji · les images | |

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
| mute someone, remove from a call | couper le micro de {name} · Retirer de l’appel / retirer de l’appel | Call moderation. "{name} muted you" → «{name} a coupé votre micro». "{name} removed you from the call." → «{name} vous a fait quitter l’appel.» "You were removed from this call." → «L’accès à cet appel vous a été retiré.» «vous a retiré» would agree with the reader (§1.11). |
| camera, microphone | la caméra · le micro | |
| connection, connecting, reconnecting | la connexion · Connexion… · Reconnexion… | "Weak connection" → «Connexion faible». "Poor connection" → «Mauvaise connexion». "Calling…" → «Appel en cours…». |
| picture-in-picture, minimize | image dans l’image · Réduire | |

### 1.5 Security and encryption

| English | fr | Notes |
|---|---|---|
| encryption, encrypted, decrypt | le chiffrement · chiffré · déchiffrer | Never «cryptage», «crypter» or «décrypter». |
| end-to-end encrypted | chiffré de bout en bout | |
| confirm (a person) | Confirmer / confirmer | "Confirmed people only" → «Personnes confirmées uniquement». |
| approve (own device) | Approuver / approuver | |
| verify, verification | vérifier · la vérification | |
| security details | les informations de sécurité | |
| key, room keys | la clé · les clés des salons | |
| backup, key backup, restore | la sauvegarde · la sauvegarde des clés · restaurer | |
| security key, security phrase, recovery key | la clé de sécurité · la phrase de sécurité · la clé de récupération | |
| cross-signing, secret storage | la signature croisée · le stockage secret | |
| session | la session | |
| unlock, trust | déverrouiller · faire confiance | |
| scan, QR code, code | Scanner · le code QR · le code | "Scan code" → «Scanner le code». |
| screenshot, screen recording, screen sharing | la capture d’écran · l’enregistrement de l’écran · le partage d’écran | |
| block | Bloquer / débloquer | |
| rooted device, compromised device | appareil rooté · appareil compromis | |
| clipboard, password manager | le presse-papiers · le gestionnaire de mots de passe | |
| incognito keyboard | Clavier incognito | |
| Cryptography | la cryptographie | Encryption stays «chiffrement». |
| raw (security key), vouch for | brute · valider | |

### 1.6 Account, server and membership

| English | fr | Notes |
|---|---|---|
| account, password | le compte · le mot de passe | "Wrong password." → «Mot de passe incorrect.» |
| username, display name | le nom d’utilisateur · le nom affiché | |
| profile, profile photo | le profil · la photo de profil | |
| email address | l’adresse e-mail | |
| invite | Inviter · l’invitation | The "Invited" badge → «Invitation envoyée». |
| withdraw (an invitation) | annuler l’invitation | "{sender} withdrew your invitation" → «{sender} a annulé votre invitation». |
| join (a room or community) | Rejoindre / rejoindre | "{people} joined" → «{people} a rejoint». |
| request, ask to join | la demande · Demander à rejoindre | "Let in" → «Accepter». "Withdraw" → «Annuler la demande». |
| leave | Quitter / quitter | "{people} left" → «{people} a quitté». |
| remove (a person) | Retirer / retirer | The kick action. |
| ban | Bannir / lever le bannissement | "Banned" heading → «Personnes bannies». |
| report | Signaler · le signalement | Reasons: «Harcèlement», «Contenu illégal», «Spam», «Autre motif». |
| public / private | public / privé | Where one label serves both a salon (m.) and a communauté (f.), recast so nothing agrees: «Accès public», «Passer en privé». |
| topic, description, address, ID | le sujet · la description · l’adresse · l’identifiant | "Room ID" → «Identifiant du salon». Room alias → «l’adresse du salon». |
| hostname | le nom du serveur | |

### 1.7 Roles and permissions

| English | fr | Notes |
|---|---|---|
| admin, moderator, owner | administrateur · modérateur · propriétaire | Role badges, generic masculine. |
| role, member, read-only, view only | le rôle · Membre · Lecture seule · Consultation uniquement | |
| permission (room or OS), access | l’autorisation · l’accès | "Roles & permissions" → «Rôles et autorisations». |

### 1.8 Notifications and push

| English | fr | Notes |
|---|---|---|
| notification, test notification | la notification · la notification de test | |
| alert | l’alerte | "Security alerts" → «Alertes de sécurité». As iOS «Alertes critiques». |
| push, push target, push key | le push · la cible push · la clé push | "push notifications" → «notifications push». |
| registration (push) | l’enregistrement / enregistrer (enregistré) | |
| delivery, background sync | la distribution · la synchronisation en arrière-plan | "Delivery method" → «Mode de distribution». |
| battery use: Unrestricted / Optimized / Restricted | utilisation de la batterie : Sans restriction / Optimisée / Restreinte | Android's labels. |
| Data Saver, Autostart | Économiseur de données · Démarrage automatique | |
| distributor | le distributeur | |
| Google services / Google Play services | les services Google / les services Google Play | |
| Apple push | le push d’Apple | |
| gateway, bridge, token | la passerelle · le pont · le jeton | |
| diagnostics | le diagnostic | |
| notification category, notification shade | la catégorie de notifications · le volet des notifications | |
| lock screen | l’écran de verrouillage | |
| quiet, sound, vibration | silencieuses · le son · la vibration | "Message tone" → «Son des messages». |
| standby bucket | le groupe de veille | |

### 1.9 Location

| English | fr | Notes |
|---|---|---|
| location, live location | la position · la position en direct | |
| share, start / stop sharing | Partager · Démarrer / Arrêter le partage | Also for sharing files. |
| approximate, maps app | approximative · l’app de cartes | |

### 1.10 Settings, storage and data

| English | fr | Notes |
|---|---|---|
| Settings | les Paramètres | Zuno's and Android's. The iOS Settings app is «Réglages» (§2.8). |
| storage, data, cache | le stockage · les données · le cache | "Clear cache" → «Vider le cache». |
| theme: Dark / Light / Follow system | Sombre / Clair / Selon le système | |
| Appearance / About / Advanced, version, build | Apparence / À propos / Avancé · la version · la compilation | |
| feedback, crash reports | les commentaires · les rapports de plantage | "Send feedback" → «Envoyer des commentaires». |
| donate, privacy, Privacy policy, Terms | faire un don · la confidentialité · Politique de confidentialité · Conditions d’utilisation | |
| app, home screen, shortcut, launcher | l’app · l’écran d’accueil · le raccourci · le lanceur d’applications | «app» is feminine. |
| recent apps, app switcher | les apps récentes · le sélecteur d’apps | |
| Open source licenses, Source code | Licences open source · Code source | |

### 1.11 Settled phrases

| English | fr | Notes |
|---|---|---|
| Asking to join (admin heading) | Demandes d’accès | "Asking to join {name}" → «Demandes d’accès à « {name} »». |
| Ask to join (subtitle) / Asks to join | Demandent à rejoindre / Demande à rejoindre | The button stays «Demander à rejoindre». |
| Let them ask (setting) | Autoriser les demandes | |
| Joined (label on a public room or community) | Déjà membre | |
| N other(s) | {count} autre personne · {count} autres personnes | |
| asleep (device) / suspended (app) | en veille / suspendue | «suspendue» agrees with «l’app». |
| Call rang / ringing | L’appel a sonné / sonne | |
| Hidden message | le message masqué | Never «secret». |
| Secure backup (screen) | «Récupération» | |
| Welcome to Zuno | Bienvenue dans Zuno | |
| {name} is confirmed | Vous avez confirmé {name} | |
| Make {people} an admin / You are now an admin (room updates) | {sender} a donné le rôle « Administrateur » à {people} / Vous avez désormais le rôle « Administrateur » | Every role the same way, with its exact label: «nommer administrateur» would agree with the person. |
| {sender} invited / removed / banned you (room updates) | {sender} vous a envoyé une invitation / vous a fait quitter le salon / a prononcé votre bannissement | «vous a invité», «vous a retiré» and «vous a banni» agree with the reader; «fait» before an infinitive never agrees. |
| joined and left (room update) | a rejoint puis quitté | |
| character(s), link, check mark | le caractère · le lien · la coche | |

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

## 2. French rules

### 2.1 Register
- «vous» throughout, never «tu».
- "tap" → «touchez», "type" → «saisissez» (or «tapez» for one word), "enter" → «saisissez», "choose/pick" → «choisissez», "pull down" → «tirez vers le bas».

### 2.2 Forms

| Where | Form | Example |
|---|---|---|
| Buttons, menu items, tabs, tooltips, switches, row labels | Infinitive | «Supprimer le compte», «Enregistrer», «Activer le haut-parleur» |
| Body text, hints, the next step in an error | Imperative (vous) | «Touchez pour réessayer.» |
| Titles that name something | Noun | «Paramètres du salon», «Vos appareils» |
| Titles that instruct | Imperative | «Enregistrez votre code de récupération» |
| Confirmation titles ("Delete X?") | Infinitive + « ?» | «Supprimer votre compte ?» |
| Progress labels | Noun + «…» | «Création du compte…», «Envoi…» |
| Success snack bars | Participle | «Mot de passe modifié», «Signalement envoyé» |

Statement and first-person buttons: «Elles correspondent», «Elles ne correspondent pas», «Oui, terminer», «Non, arrêter», «J’ai déjà un code».

### 2.3 Typography
- A no-break space (U+00A0) goes before «?», «:», «;» and «%», and inside guillemets: «Supprimer ?», «Taille : 3 Mo», «« {name} »». Never a regular space there, and never no space. No space in `https://`, clock values like `{minutes}:{seconds}`, or before arrows (→).
- Quotes: « » with no-break spaces inside.
- Apostrophe: the typographic ’ (U+2019) everywhere: «l’appareil». Never the straight '.
- Weekday and month names are lowercase.

### 2.4 Names
- People as objects stay bare: «Bloquer {name} ?», «Vous avez confirmé {name}».
- No reader agreement: «Connexion établie», never «connecté(e)».
- "they" → «cette personne»: "once they join" → «quand cette personne aura rejoint».

### 2.5 Fixed phrases
- Errors open with «Impossible de…»: «Impossible d’envoyer le message. Vérifiez votre connexion et réessayez.»
- "Check your connection and try again." → «Vérifiez votre connexion et réessayez.»
- "Pull down to try again." → «Tirez vers le bas pour réessayer.»
- "Too many attempts." → «Trop de tentatives.» · "Something went wrong." → «Un problème est survenu.»
- "Nobody can undo this." → always «Personne ne peut annuler cette action.»
- Never «Désolé», «Malheureusement», «avec succès» or «100 % sécurisé».

### 2.6 Numbers, dates and units
- "{date} at {time}" → «{date} à {time}» · "Until {time}" → «Jusqu’à {time}» · "{days} days ago" → «il y a {days} jours» · "{page} of {total}" → «{page} sur {total}».
- h, min, s, km and m take a no-break space before them. Bytes are octets: B → «o», KB → «Ko», MB → «Mo». «%» takes a no-break space before it (`{percent} %`).
- French `one` covers 0 and 1: «0 membre» is correct.

### 2.7 Ordinals
`securityOrdinal` precedes «mot» (masculine): `{n, select, 1{1er} 2{2e} 3{3e} other{{n}e}}`. `settingsRecoveryWordLabel` → «{position} mot». `settingsRecoveryConfirmBody` → «Saisissez le {first} et le {second} mot de votre copie enregistrée.»

### 2.8 Platform labels
- Android Settings is **Paramètres**; the iOS Settings app is **Réglages**: "Settings → General → Language & Region" → «Réglages → Général → Langue et région»; "Settings → Apps → Zuno → Language" → «Réglages → Apps → Zuno → Langue».
- iOS: «Service de localisation», «Confidentialité et sécurité», «Écran verrouillé», «Centre de notifications», «Bannières», «Pastilles», «Sons», «Afficher les aperçus», «Résumé programmé», «Alertes critiques», «Notifications urgentes», «Annoncer les notifications».

---

## 3. Worked examples

| Key | English | fr |
|---|---|---|
| `settingsDeleteAccountWarningTitle` | Delete your account? | Supprimer votre compte ? |
| `feedbackNotSent` | Feedback not sent. Check your connection and try again. | Commentaires non envoyés. Vérifiez votre connexion et réessayez. |
| `chatNotSentRetry` | Not sent · Tap to retry | Non envoyé · Touchez pour réessayer |
| `callsFailureOnAnotherDevice` | You are in this call on another device. Hang up there to join here. | Vous êtes déjà dans cet appel sur un autre appareil. Raccrochez-y pour le rejoindre ici. |
| `blockingTitle` | Block {name}? | Bloquer {name} ? |
| `matrixStateNameChanged` | `{sender} changed the room name to \"{name}\"` | `{sender} a renommé le salon en « {name} »` |
| `chatDeleteTitle` | `{count, plural, one{Delete message?} other{Delete {count} items?}}` | `{count, plural, one{Supprimer le message ?} other{Supprimer {count} éléments ?}}` |
| `matrixInvitePeopleInvited` | `{count, plural, other{{count} people invited}}` | `{count, plural, one{{count} personne invitée} other{{count} personnes invitées}}` |
| `permissionsPhotoLibraryAddUsage` | Zuno saves photos and videos to your library only when you tap Save. | Zuno enregistre des photos et des vidéos dans votre photothèque uniquement quand vous touchez « Enregistrer ». |

A space before «?», «:», «%» or inside « » in this file is the no-break space U+00A0.
