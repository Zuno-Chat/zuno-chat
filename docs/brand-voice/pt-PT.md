# Brand voice: European Portuguese (pt-PT)

European Portuguese for `lib/l10n/app_pt_PT.arb`, written for Portugal. The rules all languages share are in `translating.md`; this guide holds only what is European Portuguese. Brazilian Portuguese has its own guide (`pt-BR.md`); never mix the two.

**Binding, set by the product owner:**
- Formal third person, with no «você» and no «tu»: the verb carries the address and the pronoun is dropped. «Toque», «Introduza», «Escolha», «Já está nesta chamada», possessive «o seu/a sua».
- Chat = **conversa**, room = **sala**, community = **comunidade**. Never «grupo».
- **Zuno** is masculine and takes the article: «o Zuno», «do Zuno», and a sentence opens «O Zuno…» (the five `permissions*Usage` keys too). Likewise «o Android», «o iOS», «a Google», «a Apple».
- No Brazilianisms: never «tela», «celular», «arquivo», «usuário», «baixar», «salvar», «compartilhar», «excluir», «contato», «registro», «time», and never the gerund for an ongoing action («estar a» + infinitive instead). 1990 spelling: «ação», «atual», «receção», «facto», «contacto», «registo».
- `languageNativeName` → «Português (Portugal)».

---

## 1. Glossary

### 1.1 Brand-voice words

| English | pt-PT | Notes |
|---|---|---|
| chat (one-to-one) | a conversa · as conversas | "New chat" → «Nova conversa». The "Chats" tab → «Conversas». |
| room (group chat) | a sala · as salas | Never «canal». |
| community | a comunidade | Never «espaço» or «servidor». |
| "Group with {names}" | «Conversa com {names}» | |
| device | o dispositivo | "your device" → «o seu dispositivo». Never «telemóvel» or «sessão». |
| recovery code | o código de recuperação | Never «chave» or «palavra-passe». |
| recovery | a recuperação | "Set up recovery" → «Configurar recuperação». |
| sign in | Iniciar sessão / iniciar sessão · o início de sessão | "New sign-in" → «Novo início de sessão». A signed-in device → «dispositivo com sessão iniciada». |
| sign out | Terminar sessão / terminar sessão | "Sign out everywhere else" → «Terminar sessão em todos os outros dispositivos». |
| sign up, sign-up code | Criar conta · a inscrição · o código de inscrição | Never «registo», which is push registration. |
| server, homeserver | o servidor | |

### 1.2 People

| English | pt-PT | Notes |
|---|---|---|
| person, people | a pessoa · as pessoas | Feminine whatever the person's gender, so it never forces one. |
| user / member | o utilizador / o membro | "Unknown user" → «Utilizador desconhecido». |
| You (own name on tiles and the map) | Eu | The way pt-PT apps label the reader's own entry. |
| Someone / Anyone / Nobody / Everyone | Alguém / Qualquer pessoa / Ninguém / Todos | |

### 1.3 Messaging

| English | pt-PT | Notes |
|---|---|---|
| message | a mensagem | Composer placeholder "Message" → «Mensagem». |
| send | Enviar / enviar (enviada) | "Not sent" → «Não enviada». "Sending…" → «A enviar…». |
| reply | Responder · a resposta | "Replying to {name}" → «A responder a {name}». |
| reaction, react | a reação · reagir | |
| edit, edited | Editar · editada | The "edited" marker agrees with «mensagem». |
| delete | Eliminar / eliminar (eliminada) | "Message deleted" → «Mensagem eliminada». Never «apagar» or «excluir». |
| seen, seen by | Vista · Vista por {people} | "Not seen yet" → «Ainda não vista». |
| typing | a escrever… | "{name} is typing…" → «{name} está a escrever…». |
| mention | mencionar · a menção | "Mentions only" → «Só menções». |
| attachment, voice message | o anexo · a mensagem de voz | |
| photo / video / file | a fotografia / o vídeo / o ficheiro | |
| media, item | o conteúdo multimédia · o item (os itens) | The "Media" heading → «Multimédia». "Delete 3 items?" → «Eliminar 3 itens?». |
| caption, gallery | a legenda · a galeria | iOS Photos app → «Fotografias». |
| history | o histórico | |
| record, upload, download, reload | gravar · enviar · transferir · recarregar | "Uploading…" → «A enviar…». "Downloading…" → «A transferir…». «A carregar…» is Loading only. |
| emoji, verification emoji | o emoji · as imagens | |

### 1.4 Calls

| English | pt-PT | Notes |
|---|---|---|
| call, voice call, video call | a chamada · a chamada de voz · a videochamada | Button "Call" → «Ligar». |
| ring, ringtone, full screen | tocar (toca, tocou) · o toque · o ecrã inteiro | |
| incoming / missed / ongoing call | chamada recebida / perdida / em curso | "Missed call from {name}" → «Chamada perdida de {name}». |
| Accept / Decline | Aceitar / Recusar | Also for invites and requests. |
| hang up, End call | Terminar chamada / terminar | |
| join (a call) | Participar / participar na chamada | |
| speaker, mute, unmute | o altifalante · Silenciar · Ativar som | "Muted" → «Silenciado». |
| camera, microphone | a câmara · o microfone | "Switch camera" → «Mudar de câmara». |
| connection, connecting, reconnecting | a ligação · A estabelecer ligação… · A restabelecer ligação… | "Weak connection" → «Ligação fraca». "Poor connection" → «Má ligação». "Calling…" → «A chamar…». The sign-in button's "Connecting…" → «A ligar…». |
| picture-in-picture, minimize | ecrã no ecrã · Minimizar | |

### 1.5 Security and encryption

| English | pt-PT | Notes |
|---|---|---|
| encryption, encrypted, decrypt | a encriptação · encriptado · desencriptar | |
| end-to-end encrypted | com encriptação ponto a ponto | |
| confirm (a person) | Confirmar / confirmar | "Confirmed people only" → «Só pessoas confirmadas». |
| approve (own device) | Aprovar / aprovar | |
| verify, verification | verificar · a verificação | |
| security details | os dados de segurança | |
| key, room keys | a chave · as chaves das salas | |
| backup, key backup, restore | a cópia de segurança · a cópia de segurança das chaves · restaurar | |
| security key, security phrase, recovery key | a chave de segurança · a frase de segurança · a chave de recuperação | |
| cross-signing, secret storage | a assinatura cruzada · o armazenamento secreto | |
| session | a sessão | |
| unlock, trust | desbloquear · confiar | |
| scan, QR code, code | Ler · o código QR · o código | "Scan code" → «Ler código». A bare «código» is never a password. |
| screenshot, screen recording, screen sharing | a captura de ecrã · a gravação de ecrã · a partilha de ecrã | |
| block | Bloquear / desbloquear | |
| rooted device, compromised device | dispositivo com root · dispositivo comprometido | |
| clipboard, password manager | a área de transferência · o gestor de palavras-passe | |
| incognito keyboard | Teclado anónimo | |
| Cryptography | a criptografia | Encryption stays «encriptação». |
| raw (security key), vouch for (own devices) | em bruto · validar | |

### 1.6 Account, server and membership

| English | pt-PT | Notes |
|---|---|---|
| account, password | a conta · a palavra-passe | Always in full. "Wrong password." → «Palavra-passe incorreta.» |
| username, display name | o nome de utilizador · o nome a apresentar | |
| profile, profile photo | o perfil · a fotografia de perfil | |
| email address | o endereço de email | |
| invite | Convidar · o convite | The "Invited" badge → «Convite enviado». |
| join (a room or community) | Entrar / entrar | "{target} joined" → «{target} entrou». |
| request, ask to join | o pedido · Pedir para entrar | "Let in" → «Aceitar». "Withdraw" → «Cancelar pedido». |
| leave | Sair / sair (saiu) | |
| remove (a person or item) | Remover / remover | The kick action. |
| ban | Banir / anular banimento | "Banned" heading → «Banidos». |
| report | Denunciar · a denúncia | Reasons: «Assédio», «Conteúdo ilegal», «Spam», «Outro motivo». |
| public / private | pública / privada | Feminine, agreeing with sala and comunidade. |
| topic, description, address, ID | o tópico · a descrição · o endereço · o ID | Room alias → «o endereço da sala». |
| hostname | o nome do servidor | |

### 1.7 Roles and permissions

| English | pt-PT | Notes |
|---|---|---|
| admin, moderator, owner | administrador · moderador · proprietário | Role badges, generic masculine. |
| role, member, read-only, view only | a função · Membro · Só de leitura · Só de consulta | |
| permission (room or OS), access | a permissão · o acesso | |

### 1.8 Notifications and push

| English | pt-PT | Notes |
|---|---|---|
| notification, test notification | a notificação · a notificação de teste | |
| push, push target, push key | o push · o destino push · a chave push | "push notifications" → «notificações push». |
| registration (push) | o registo / registar (registado) | Never «inscrição», which is sign-up. |
| delivery, background sync | a entrega · a sincronização em segundo plano | |
| battery use: Unrestricted / Optimized / Restricted | utilização da bateria: Sem restrições / Otimizada / Restrita | Android's labels. |
| Data Saver, Autostart | Poupança de dados · Arranque automático | |
| distributor | o distribuidor | |
| Google services / Google Play services | os serviços Google / os Serviços do Google Play | |
| Apple push | o push da Apple | |
| gateway, bridge, token | o gateway · a ponte · o token | |
| diagnostics | o Diagnóstico | |
| notification category, notification shade | a categoria de notificação · o painel de notificações | |
| lock screen | o ecrã de bloqueio | |
| quiet, sound, vibration | silenciosas · o som · a vibração | "Message tone" → «Som de mensagem». |
| standby bucket | o grupo de espera | |

### 1.9 Location

| English | pt-PT | Notes |
|---|---|---|
| location, live location | a localização · a localização em tempo real | |
| share, start / stop sharing | Partilhar · Iniciar / Parar partilha | Also for sharing files. |
| approximate, maps app | aproximada · a app de mapas | |

### 1.10 Settings, storage and data

| English | pt-PT | Notes |
|---|---|---|
| Settings | as Definições | Zuno's, Android's and iOS's (§2.8). |
| storage, data, cache | o armazenamento · os dados · a cache | "Clear cache" → «Limpar cache». |
| theme: Dark / Light / Follow system | Escuro / Claro / Predefinição do sistema | |
| Appearance / About / Advanced, version, build | Aspeto / Acerca de / Avançado · a versão · a compilação | |
| feedback, crash reports | os comentários · os relatórios de falhas | "Send feedback" → «Enviar comentários». |
| donate, privacy, Privacy policy, Terms | doar · a privacidade · Política de privacidade · Termos | |
| app, home screen, shortcut, launcher | a app · o ecrã principal · o atalho · o iniciador | «app» is feminine. |
| recent apps, app switcher | as apps recentes · o seletor de apps | |
| Open source licenses, Source code | Licenças de código aberto · Código-fonte | |

### 1.11 Settled phrases

| English | pt-PT | Notes |
|---|---|---|
| Asking to join (admin heading) | Pedidos de entrada | Never «A pedir para entrar». "Asking to join {name}" → «Pedidos de entrada em «{name}»». |
| Ask to join (subtitle) / Asks to join | Pedem para entrar / Pede para entrar | The button stays «Pedir para entrar». |
| Let them ask (setting) | Permitir pedidos | |
| Joined (label on a public room) | Já participa | |
| N other(s) | {count} outra pessoa · {count} outras pessoas | |
| asleep (device) / suspended (app) | em repouso / suspensa | «suspensa» agrees with «a app». |
| Call rang / ringing | A chamada tocou / a tocar | |
| Hidden message | a mensagem oculta | Never «secreta». |
| Secure backup (screen) | «Recuperação» | |
| Welcome to Zuno | Boas-vindas ao Zuno | «Bem-vindo» would force a gender. |
| Invited you to {room} / wants to verify you | Enviou-lhe um convite para «{room}» / Pede uma verificação | Recast so no participle or pronoun agrees with the reader. |
| Only you and {name} | Ninguém além de si e de {name} | |
| link | o link | Never «ligação», which is connection. |
| character(s), check mark | o carácter (os caracteres) · o visto | |

### 1.12 UI actions

| English | pt-PT |
|---|---|
| Cancel / Save / Saved | Cancelar / Guardar / Guardado |
| Delete / Remove | Eliminar / Remover |
| Copy / Copied / Share | Copiar / Copiado / Partilhar |
| Send / Continue / Continue anyway | Enviar / Continuar / Continuar mesmo assim |
| Done / Retry / Try again | Concluído / Tentar novamente / Tentar novamente |
| Close / Dismiss / Open / Open settings | Fechar / Ignorar / Abrir / Abrir definições |
| Turn on / Turn off · On / Off | Ativar / Desativar · Ativado / Desativado |
| Allow / Not now / Skip | Permitir / Agora não / Saltar |
| Confirm / Approve | Confirmar / Aprovar |
| Create / Start / Get started | Criar / Iniciar / Começar |
| Edit / Change / Review | Editar / Alterar / Rever |
| Back / Stop / Play | Voltar / Parar / Reproduzir |
| Read more / Show less | Ver mais / Ver menos |
| Mark as read / Unread | Marcar como lida / Não lidas |
| Refresh / Search / Start over | Atualizar / Pesquisar / Recomeçar |

### 1.13 Status words

| English | pt-PT |
|---|---|
| Loading… / Sending… / Waiting… | A carregar… / A enviar… / A aguardar… |
| Checking… / Searching… | A verificar… / A procurar… |
| Failed | Falhou |
| Not set / Unknown / None / Never | Não definido / Desconhecido / Nenhum / Nunca |
| Not available / Yes / No | Indisponível / Sim / Não |
| Just now / Today / Yesterday / Coming soon | Agora mesmo / Hoje / Ontem / Em breve |

---

## 2. European Portuguese rules

### 2.1 Register
- Formal third person with the pronoun dropped: «Já está nesta chamada noutro dispositivo.», «A sua conta foi eliminada.» Never «você», never «tu», never «o senhor».
- Possessives take the article: «a sua conta», «o seu dispositivo».
- Questions to the reader: «Pretende…?» or an infinitive title (§2.2).
- "tap" → «toque», "type" → «escreva», "enter" → «introduza», "choose/pick" → «escolha», "pull down" → «puxe para baixo».
- Contract prepositions: «noutro», «nesta», «num», «numa».

### 2.2 Forms

| Where | Form | Example |
|---|---|---|
| Buttons, menu items, tabs, tooltips, switches, row labels | Infinitive | «Eliminar conta», «Guardar», «Ativar altifalante» |
| Body text, hints, the next step in an error | Formal imperative | «Toque para tentar novamente.» |
| Titles that name something | Noun | «Definições da sala», «Os seus dispositivos» |
| Titles that instruct | Formal imperative | «Guarde o seu código de recuperação» |
| Confirmation titles ("Delete X?") | Infinitive + «?» | «Eliminar a sua conta?» |
| Progress labels | «A» + infinitive + «…» | «A criar conta…» |
| Success snack bars | Participle, English period kept or left out | «Palavra-passe alterada», «Denúncia enviada» |

Statement and first-person buttons: «Coincidem», «Não coincidem», «Sim, concluir», «Não, parar», «Já tenho um código».

### 2.3 Typography
- Quotes: « », as in `«{name}»`.
- Colons keep the English spacing.
- Weekday and month names are lowercase.

### 2.4 Names
- No article before a name: never «o {name}» or «da {name}».
- Subject names go first, bare: «{name} saiu», «{target} entrou».
- Short labels: «Com {name}», «A responder a {name}», «Chamada perdida de {name}».
- Verbs avoid agreement: «Bloquear {name}?», «{name} confirmou», «Confirmou {name}». Where a noun is needed, «a pessoa».
- "they" → «a pessoa» or drop the subject: "once they join" → «quando a pessoa entrar».

### 2.5 Fixed phrases
- Error pattern: «Não foi possível enviar a mensagem. Verifique a ligação e tente novamente.»
- "Check your connection and try again." → «Verifique a ligação e tente novamente.»
- "Pull down to try again." → «Puxe para baixo para tentar novamente.»
- "Too many attempts." → «Demasiadas tentativas.» · "Something went wrong." → «Ocorreu um problema.»
- "Nobody can undo this." → always «Ninguém pode desfazer isto.»
- Never «Lamentamos», «Infelizmente», «com sucesso» or «100% seguro».

### 2.6 Numbers, dates and units
- "{date} at {time}" → «{date} às {time}» · "Until {time}" → «Até às {time}» · "{days} days ago" → «há {days} dias» · "{page} of {total}" → «{page} de {total}».
- European `one` is exactly 1: the number is always `{count}`, never «uma» or «1».

### 2.7 Ordinals
`securityOrdinal` precedes «palavra» (feminine): `{n, select, 1{1.ª} 2{2.ª} 3{3.ª} other{{n}.ª}}`. `settingsRecoveryWordLabel` → «{position} palavra». `settingsRecoveryConfirmBody` → «Escreva a {first} e a {second} palavras da cópia que guardou.»

### 2.8 Platform labels
- Android and iOS both call Settings **Definições**: "Settings → General → Language & Region" → «Definições → Geral → Idioma e região»; "Settings → Apps → Zuno → Language" → «Definições → Apps → Zuno → Idioma».
- iOS: «Serviços de localização», «Privacidade e segurança», «Ecrã bloqueado», «Central de notificações», «Faixas», «Etiquetas», «Sons», «Mostrar pré-visualizações», «Resumo agendado», «Alertas críticos», «Notificações urgentes», «Anunciar notificações».

---

## 3. Worked examples

| Key | English | pt-PT |
|---|---|---|
| `settingsDeleteAccountWarningTitle` | Delete your account? | Eliminar a sua conta? |
| `feedbackNotSent` | Feedback not sent. Check your connection and try again. | Comentários não enviados. Verifique a ligação e tente novamente. |
| `chatNotSentRetry` | Not sent · Tap to retry | Não enviada · Toque para tentar novamente |
| `callsFailureOnAnotherDevice` | You are in this call on another device. Hang up there to join here. | Já está nesta chamada noutro dispositivo. Termine-a lá para participar aqui. |
| `settingsAccountPasswordChanged` | Password changed | Palavra-passe alterada |
| `blockingTitle` | Block {name}? | Bloquear {name}? |
| `matrixStateNameChanged` | `{sender} changed the room name to \"{name}\"` | `{sender} mudou o nome da sala para «{name}»` |
| `chatDeleteTitle` | `{count, plural, one{Delete message?} other{Delete {count} items?}}` | `{count, plural, one{Eliminar mensagem?} other{Eliminar {count} itens?}}` |
| `matrixInvitePeopleInvited` | `{count, plural, other{{count} people invited}}` | `{count, plural, one{{count} pessoa convidada} other{{count} pessoas convidadas}}` |
| `permissionsPhotoLibraryAddUsage` | Zuno saves photos and videos to your library only when you tap Save. | O Zuno guarda fotografias e vídeos na sua fototeca só quando toca em «Guardar». |
