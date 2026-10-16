# Brand voice: Spanish (es)

Spanish for `lib/l10n/app_es.arb`, written for Spain and served to every Spanish-speaking region. The rules all languages share are in `translating.md`; this guide holds only what is Spanish.

**Binding, set by the product owner:**
- Address the reader as **tú**: «Toca», «Escribe», «Elige», «tu/tus».
- Chat = **chat**, room = **sala**, community = **comunidad**. Never «grupo», «canal» or «espacio».
- **Zuno**, **Matrix**, **Android**, **iOS**, **Google** and **Apple** take no article: «Zuno cifra tus mensajes», «la versión de Zuno».
- `languageNativeName` → «Español».

---

## 1. Glossary

### 1.1 Brand-voice words

| English | es | Notes |
|---|---|---|
| chat (one-to-one) | el chat · los chats | "New chat" → «Nuevo chat». The "Chats" tab → «Chats». Never «conversación» as the product noun. |
| room (group chat) | la sala · las salas | Never «habitación». |
| community | la comunidad | Never «servidor». |
| "Group with {names}" | «Chat con {names}» | |
| device | el dispositivo | Never «móvil». |
| recovery code | el código de recuperación | Never «clave» or «contraseña». |
| recovery | la recuperación | "Set up recovery" → «Configurar recuperación». |
| sign in | Iniciar sesión / iniciar sesión · el inicio de sesión | "New sign-in" → «Nuevo inicio de sesión». A signed-in device → «dispositivo con sesión iniciada». |
| sign out | Cerrar sesión / cerrar sesión | "Sign out everywhere else" → «Cerrar sesión en todos los demás dispositivos». |
| sign up, sign-up code | Crear cuenta · el registro · el código de registro | Push registration is «registro push». |
| server, homeserver | el servidor | |

### 1.2 People

| English | es | Notes |
|---|---|---|
| person, people | la persona · las personas | Grammatically feminine, so it forces no gender. |
| user / member | el usuario / el miembro | "Unknown user" → «Usuario desconocido». |
| You (own name on tiles and the map) | Tú | |
| Someone / Anyone / Nobody / Everyone | Alguien / Cualquiera / Nadie / Todos | |

### 1.3 Messaging

| English | es | Notes |
|---|---|---|
| message | el mensaje | Composer placeholder "Message" → «Mensaje». |
| send | Enviar / enviar (enviado) | "Not sent" → «No enviado». "Sending…" → «Enviando…». |
| reply | Responder · la respuesta | "Replying to {name}" → «Respondiendo a {name}». |
| reaction, react | la reacción · reaccionar | |
| edit, edited | Editar · editado | The "edited" marker agrees with «mensaje». |
| delete | Eliminar / eliminar (eliminado) | "Message deleted" → «Mensaje eliminado». Never «borrar». |
| remove (an item) | Quitar / quitar | "Remove photo" → «Quitar foto». |
| seen, seen by | Visto · Visto por {people} | "Not seen yet" → «Aún no visto». |
| typing | escribiendo… | "{name} is typing…" → «{name} está escribiendo…». |
| mention | mencionar · la mención | "Mentions only" → «Solo menciones». |
| attachment, voice message | el archivo adjunto · el mensaje de voz | |
| photo / video / file | la foto / el vídeo / el archivo | «vídeo» with the accent, as in Spain. |
| media, item | el contenido multimedia · el elemento | The "Media" heading → «Multimedia». "Delete 3 items?" → «¿Eliminar 3 elementos?». |
| caption, gallery | la descripción · la galería | iOS Photos app → «Fotos». |
| history | el historial | |
| record, upload, download, reload | grabar · subir · descargar · recargar | "Uploading…" → «Subiendo…». "Downloading…" → «Descargando…». «Cargando…» is Loading only. |
| emoji, verification emoji | el emoji · las imágenes | |

### 1.4 Calls

| English | es | Notes |
|---|---|---|
| call, voice call, video call | la llamada · la llamada de voz · la videollamada | Button "Call" → «Llamar». |
| ring, ringtone, full screen | sonar · el tono de llamada · pantalla completa | |
| incoming / missed / ongoing call | llamada entrante / perdida / en curso | "Missed call from {name}" → «Llamada perdida de {name}». |
| Accept / Decline | Aceptar / Rechazar | Also for invites and requests. |
| hang up, End call | Colgar | Both. |
| join (a call) | Unirse / unirse a la llamada | |
| speaker, mute, unmute | el altavoz · Silenciar · Activar micrófono | "Muted" → «Silenciado». "{name} is muted" → «{name} tiene el micrófono silenciado». |
| camera, microphone | la cámara · el micrófono | |
| connection, connecting, reconnecting | la conexión · Conectando… · Reconectando… | "Weak connection" → «Conexión débil». "Poor connection" → «Mala conexión». "Calling…" → «Llamando…». |
| picture-in-picture, minimize | imagen en imagen · Minimizar | |

### 1.5 Security and encryption

| English | es | Notes |
|---|---|---|
| encryption, encrypted, decrypt | el cifrado · cifrado · descifrar | Never «encriptación» or «encriptar». |
| end-to-end encrypted | cifrado de extremo a extremo | |
| confirm (a person) | Confirmar / confirmar | "Confirmed people only" → «Solo personas confirmadas». |
| approve (own device) | Aprobar / aprobar | |
| verify, verification | verificar · la verificación | |
| security details | los datos de seguridad | |
| key, room keys | la clave · las claves de las salas | |
| backup, key backup, restore | la copia de seguridad · la copia de seguridad de claves · restaurar | |
| security key, security phrase, recovery key | la clave de seguridad · la frase de seguridad · la clave de recuperación | |
| cross-signing, secret storage | la firma cruzada · el almacenamiento secreto | |
| session | la sesión | |
| unlock, trust | desbloquear · confiar | |
| scan, QR code, code | Escanear · el código QR · el código | "Scan code" → «Escanear código». A bare «código» is never a password. |
| screenshot, screen recording, screen sharing | la captura de pantalla · la grabación de pantalla · compartir pantalla | |
| block | Bloquear / desbloquear | |
| rooted device, compromised device | dispositivo rooteado · dispositivo comprometido | |
| clipboard, password manager | el portapapeles · el gestor de contraseñas | |
| incognito keyboard | Teclado de incógnito | |
| Cryptography | la criptografía | Encryption stays «cifrado». |
| raw (security key), vouch for | sin formato · validar | |

### 1.6 Account, server and membership

| English | es | Notes |
|---|---|---|
| account, password | la cuenta · la contraseña | "Wrong password." → «Contraseña incorrecta.» |
| username, display name | el nombre de usuario · el nombre visible | |
| profile, profile photo | el perfil · la foto de perfil | |
| email address | la dirección de correo electrónico | Short form «correo». |
| invite | Invitar · la invitación | The "Invited" badge → «Invitación enviada». |
| join (a room or community) | Unirse / unirse | "{target} joined" → «{target} se ha unido». |
| request, ask to join | la solicitud · Solicitar unirse | "Let in" → «Aceptar». "Withdraw" → «Retirar solicitud». |
| leave | Salir / salir | "{target} left" → «{target} ha salido». |
| remove (a person) | Expulsar / expulsar | The kick action. |
| ban | Vetar / quitar el veto | "Banned" heading → «Personas vetadas». |
| report | Denunciar · la denuncia | Reasons: «Acoso», «Contenido ilegal», «Spam», «Otro motivo». |
| public / private | pública / privada | Feminine, agreeing with sala and comunidad. |
| topic, description, address, ID | el tema · la descripción · la dirección · el ID | Room alias → «la dirección de la sala». |
| hostname | el nombre del servidor | |

### 1.7 Roles and permissions

| English | es | Notes |
|---|---|---|
| admin, moderator, owner | administrador · moderador · propietario | Role badges, generic masculine. |
| role, member, read-only, view only | el rol · Miembro · Solo lectura · Solo consulta | |
| permission (room or OS), access | el permiso · el acceso | "Roles & permissions" → «Roles y permisos». |

### 1.8 Notifications and push

| English | es | Notes |
|---|---|---|
| notification, test notification | la notificación · la notificación de prueba | |
| alert | el aviso | "Security alerts" → «Avisos de seguridad». As iOS «Avisos críticos»; never «alerta». |
| mute / unmute (a chat's notifications) | Silenciar / Dejar de silenciar | |
| push, push target, push key | el push · el destino push · la clave push | "push notifications" → «notificaciones push». |
| registration (push) | el registro / registrar (registrado) | |
| delivery, background sync | la entrega · la sincronización en segundo plano | "Delivery method" → «Método de entrega». |
| battery use: Unrestricted / Optimized / Restricted | uso de batería: Sin restricciones / Optimizado / Restringido | Android's labels. |
| Data Saver, Autostart | Ahorro de datos · Inicio automático | |
| distributor | el distribuidor | |
| Google services / Google Play services | los servicios de Google / los servicios de Google Play | |
| Apple push | el push de Apple | |
| gateway, bridge, token | la pasarela · el puente · el token | |
| diagnostics | el diagnóstico | |
| notification category, notification shade | la categoría de notificaciones · el panel de notificaciones | |
| lock screen | la pantalla de bloqueo | |
| quiet, sound, vibration | silenciosas · el sonido · la vibración | "Message tone" → «Tono de mensaje». |
| standby bucket | el grupo de inactividad | |

### 1.9 Location

| English | es | Notes |
|---|---|---|
| location, live location | la ubicación · la ubicación en tiempo real | |
| share, start / stop sharing | Compartir · Empezar / Dejar de compartir | Also for sharing files. |
| approximate, maps app | aproximada · la app de mapas | |

### 1.10 Settings, storage and data

| English | es | Notes |
|---|---|---|
| Settings | los Ajustes | Zuno's, Android's and iOS's. |
| storage, data, cache | el almacenamiento · los datos · la caché | "Clear cache" → «Borrar caché». |
| theme: Dark / Light / Follow system | Oscuro / Claro / Predeterminado del sistema | |
| Appearance / About / Advanced, version, build | Apariencia / Información / Avanzado · la versión · la compilación | |
| feedback, crash reports | los comentarios · los informes de fallos | "Send feedback" → «Enviar comentarios». |
| donate, privacy, Privacy policy, Terms | donar · la privacidad · Política de privacidad · Términos | |
| app, home screen, shortcut, launcher | la app · la pantalla de inicio · el acceso directo · el launcher | «app» is feminine. |
| recent apps, app switcher | las apps recientes · el selector de apps | |
| Open source licenses, Source code | Licencias de código abierto · Código fuente | |

### 1.11 Settled phrases

| English | es | Notes |
|---|---|---|
| Asking to join (admin heading) | Solicitudes para unirse | "Asking to join {name}" → «Solicitudes para unirse a «{name}»». |
| Ask to join (subtitle) / Asks to join | Solicitan unirse / Solicita unirse | The button stays «Solicitar unirse». |
| Let them ask (setting) | Permitir solicitudes | |
| Joined (label on a public room or community) | Ya eres miembro | |
| N other(s) | {count} persona más · {count} personas más | |
| asleep (device) / suspended (app) | en reposo / suspendida | «suspendida» agrees with «la app». |
| Call rang / ringing | La llamada sonó / sonando | |
| Hidden message | el mensaje oculto | Never «secreto». |
| Secure backup (screen) | «Recuperación» | |
| Welcome to Zuno | Zuno te da la bienvenida | «Bienvenido» would force a gender. |
| {name} is confirmed | Has confirmado a {name} | |
| Confirmed (title after confirming a person) | Confirmación completada | |
| Make someone else an admin | da a otra persona el rol de administrador | «nombra administrador a…» would agree with the person. |
| Room / Community defaults | Valores predeterminados de la sala / de la comunidad | |
| "You and {name} are…" | Recast so the verb is not plural «vosotros»: «Ubicación en tiempo real compartida por ti y {name}». | |
| character(s), link, check mark | el carácter · los caracteres · el enlace · la marca de verificación | |

### 1.12 UI actions

| English | es |
|---|---|
| Cancel / Save / Saved | Cancelar / Guardar / Guardado |
| Delete / Remove | Eliminar / Quitar |
| Copy / Copied / Share | Copiar / Copiado / Compartir |
| Send / Continue / Continue anyway | Enviar / Continuar / Continuar de todos modos |
| Done / Retry / Try again | Hecho / Reintentar / Volver a intentarlo |
| Close / Dismiss / Open / Open settings | Cerrar / Descartar / Abrir / Abrir ajustes |
| Turn on / Turn off · On / Off | Activar / Desactivar · Activado / Desactivado |
| Allow / Not now / Skip | Permitir / Ahora no / Omitir |
| Confirm / Approve | Confirmar / Aprobar |
| Create / Start / Get started | Crear / Iniciar / Empezar |
| Edit / Change / Review | Editar / Cambiar / Revisar |
| Back / Stop / Play | Atrás / Detener / Reproducir |
| Read more / Show less | Leer más / Ver menos |
| Mark as read / Unread | Marcar como leído / No leídos |
| Refresh / Search / Start over | Actualizar / Buscar / Empezar de nuevo |

### 1.13 Status words

| English | es |
|---|---|
| Loading… / Sending… / Waiting… | Cargando… / Enviando… / Esperando… |
| Checking… / Searching… | Comprobando… / Buscando… |
| Failed | Error |
| Not set / Unknown / None / Never | Sin definir / Desconocido / Ninguno / Nunca |
| Not available / Yes / No | No disponible / Sí / No |
| Just now / Today / Yesterday / Coming soon | Ahora mismo / Hoy / Ayer / Próximamente |

---

## 2. Spanish rules

### 2.1 Register
- «tú» throughout, usually left implicit: «Toca para volver a intentarlo», «Tu cuenta se ha eliminado». Never «usted», never «vosotros».
- "tap" → «toca», "type" → «escribe», "enter" → «introduce», "choose/pick" → «elige», "pull down" → «desliza hacia abajo».
- Spain's usage: «móvil» never appears (§1.1), «vídeo» with accent, pretérito perfecto for recent events («se ha unido», «ha salido»).

### 2.2 Forms

| Where | Form | Example |
|---|---|---|
| Buttons, menu items, tabs, tooltips, switches, row labels | Infinitive | «Eliminar cuenta», «Guardar», «Activar altavoz» |
| Body text, hints, the next step in an error | Imperative (tú) | «Toca para volver a intentarlo.» |
| Titles that name something | Noun | «Ajustes de la sala», «Tus dispositivos» |
| Titles that instruct | Imperative | «Guarda tu código de recuperación» |
| Confirmation titles ("Delete X?") | ¿Infinitive? | «¿Eliminar tu cuenta?» |
| Progress labels | Gerund + «…» | «Creando cuenta…» |
| Success snack bars | Participle | «Contraseña cambiada», «Denuncia enviada» |

Statement and first-person buttons: «Coinciden», «No coinciden», «Sí, terminar», «No, parar», «Ya tengo un código».

### 2.3 Typography
- Every question opens with «¿» where the question starts: «¿Eliminar tu cuenta?», «Código perdido. ¿Empezar de nuevo?». Never «¡».
- Quotes: « » with no inner spaces: `«{name}»`.
- Colons stay exactly as in the English.
- Weekday and month names are lowercase.

### 2.4 Names
- A person as direct object always takes the personal «a»: «¿Bloquear a {name}?», «Has confirmado a {name}», «{sender} ha invitado a {target}», «{sender} ha expulsado a {target}».
- Compound tenses with «haber» never agree, so prefer them: «{name} ha salido», «{target} se ha unido».
- No agreement with a person: never «conectado/a», «bloqueado/a» or «invitado/a» about a person. Verbs and nouns avoid it: «Sesión iniciada», «Has bloqueado a {name}».
- "they" → «esta persona» or drop the subject: "once they join" → «cuando esta persona se una». No «x» or «-e» endings.

### 2.5 Fixed phrases
- Error pattern: «No se ha podido enviar el mensaje. Comprueba la conexión y vuelve a intentarlo.»
- "Check your connection and try again." → «Comprueba la conexión y vuelve a intentarlo.»
- "Pull down to try again." → «Desliza hacia abajo para volver a intentarlo.»
- "Too many attempts." → «Demasiados intentos.» · "Something went wrong." → «Algo ha salido mal.»
- "Nobody can undo this." → always «Nadie puede deshacer esta acción.»
- Never «Lo sentimos», «Lamentablemente», «correctamente», «con éxito» or «100 % seguro».

### 2.6 Numbers, dates and units
- "{date} at {time}" → «{date} a las {time}» · "Until {time}" → «Hasta las {time}» · "{days} days ago" → «hace {days} días» · "{page} of {total}" → «{page} de {total}».
- «%» takes a no-break space (U+00A0) before it: `{percent} %`.
- Spanish `one` is exactly 1.

### 2.7 Ordinals
`securityOrdinal` precedes «palabra» (feminine): `{n, select, 1{1.ª} 2{2.ª} 3{3.ª} other{{n}.ª}}`. `settingsRecoveryWordLabel` → «{position} palabra». `settingsRecoveryConfirmBody` → «Escribe la {first} y la {second} palabra de tu copia guardada.»

### 2.8 Platform labels
- Android and iOS both call Settings **Ajustes**: "Settings → General → Language & Region" → «Ajustes → General → Idioma y región»; "Settings → Apps → Zuno → Language" → «Ajustes → Apps → Zuno → Idioma».
- iOS: «Localización», «Privacidad y seguridad», «Pantalla bloqueada», «Centro de notificaciones», «Banners», «Globos», «Sonidos», «Mostrar previsualizaciones», «Resumen programado», «Avisos críticos», «Notificaciones urgentes», «Anunciar notificaciones».

---

## 3. Worked examples

| Key | English | es |
|---|---|---|
| `settingsDeleteAccountWarningTitle` | Delete your account? | ¿Eliminar tu cuenta? |
| `feedbackNotSent` | Feedback not sent. Check your connection and try again. | Comentarios no enviados. Comprueba la conexión y vuelve a intentarlo. |
| `chatNotSentRetry` | Not sent · Tap to retry | No enviado · Toca para reintentar |
| `callsFailureOnAnotherDevice` | You are in this call on another device. Hang up there to join here. | Ya estás en esta llamada en otro dispositivo. Cuelga allí para unirte aquí. |
| `settingsAccountPasswordChanged` | Password changed | Contraseña cambiada |
| `blockingTitle` | Block {name}? | ¿Bloquear a {name}? |
| `matrixStateNameChanged` | `{sender} changed the room name to \"{name}\"` | `{sender} ha cambiado el nombre de la sala a «{name}»` |
| `chatDeleteTitle` | `{count, plural, one{Delete message?} other{Delete {count} items?}}` | `{count, plural, one{¿Eliminar mensaje?} other{¿Eliminar {count} elementos?}}` |
| `matrixInvitePeopleInvited` | `{count, plural, other{{count} people invited}}` | `{count, plural, one{{count} persona invitada} other{{count} personas invitadas}}` |
| `permissionsPhotoLibraryAddUsage` | Zuno saves photos and videos to your library only when you tap Save. | Zuno guarda fotos y vídeos en tu fototeca solo cuando tocas «Guardar». |
