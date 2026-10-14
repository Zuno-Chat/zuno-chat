# Brand voice: Brazilian Portuguese (pt-BR)

How Zuno sounds in Brazilian Portuguese: the glossary and style rules behind `lib/l10n/app_pt.arb`. Every new English string gets its Portuguese from here. A string that needs a term this guide lacks adds the term here first. European Portuguese has its own guide (`brand-voice-pt-PT.md`); never mix the two.

**Binding, set by the product owner:**
- Address the reader as **você**: «Toque», «Digite», «Escolha», possessive «seu/sua».
- Room = **sala**, chat = **conversa**, community = **comunidade**. They never overlap; «grupo» is never used.
- **Zuno** and **Matrix** stay exactly as written. Zuno is masculine: «o Zuno», «do Zuno».

---

## 1. Glossary

Where a row has two forms, the first is the button/noun form and the second the verb used in body text (§2.2).

### 1.1 Brand-voice words

| English | pt-BR | Notes |
|---|---|---|
| chat (one-to-one) | a conversa · as conversas | "New chat" → «Nova conversa». The "Chats" tab → «Conversas». Never «chat» or «bate-papo». |
| room (group chat) | a sala · as salas | Never «grupo» or «canal». |
| community | a comunidade | Never «espaço» or «servidor». |
| "Group with {names}" | «Conversa com {names}» | |
| device | o dispositivo | Never «celular» or «sessão», even when the description says "phone". |
| recovery code | o código de recuperação | The 12 words. Never «chave» or «senha». |
| recovery | a recuperação | "Set up recovery" → «Configurar recuperação». |
| sign in | Entrar / entrar (entre, entrou) · o login | "New sign-in" → «Novo login». A signed-in device → «dispositivo conectado» (or «onde você entrou»). |
| sign out | Sair / sair (saia, saiu) | "Sign out everywhere else" → «Sair de todos os outros dispositivos». |
| sign up, sign-up code | Criar conta · o cadastro · o código de cadastro | Never for push registration (§1.8). |
| server, homeserver | o servidor | |

### 1.2 People

| English | pt-BR | Notes |
|---|---|---|
| person, people | a pessoa · as pessoas | Feminine whatever the person's gender, so it never forces one. |
| user / member | o usuário / o membro | "Unknown user" → «Usuário desconhecido». |
| You (own name on tiles and the map) | Você | |
| Someone / Anyone / Nobody / Everyone | Alguém / Qualquer pessoa / Ninguém / Todos | |

### 1.3 Messaging

| English | pt-BR | Notes |
|---|---|---|
| message | a mensagem | Composer placeholder "Message" → «Mensagem». |
| send | Enviar / enviar (enviada) | "Not sent" → «Não enviada». "Sending…" → «Enviando…». |
| reply | Responder · a resposta | "Replying to {name}" → «Respondendo a {name}». |
| reaction, react | a reação · reagir | |
| edit, edited | Editar · editada | The "edited" marker agrees with «mensagem». |
| delete | Excluir / excluir (excluída) | "Message deleted" → «Mensagem excluída». Never «apagar» or «deletar». |
| seen, seen by | Visualizada · Visualizada por {people} | "Not seen yet" → «Ainda não visualizada». |
| typing | digitando… | "{name} is typing…" → «{name} está digitando…». |
| mention | mencionar · a menção | "Mentions only" → «Só menções». |
| attachment, voice message | o anexo · a mensagem de voz | |
| photo / video / file | a foto / o vídeo / o arquivo | |
| media, item | a mídia · o item (os itens) | "Delete 3 items?" → «Excluir 3 itens?». |
| caption, gallery | a legenda · a galeria | iOS Photos app → «Fotos». |
| history | o histórico | |
| record, upload, download, reload | gravar · enviar · baixar · recarregar | "Uploading…" → «Enviando…». "Downloading…" → «Baixando…». |
| emoji | o emoji | The verification emoji are «imagens», as in the English. |

### 1.4 Calls

| English | pt-BR | Notes |
|---|---|---|
| call, voice call, video call | a chamada · a chamada de voz · a chamada de vídeo | Button "Call" → «Ligar». |
| ring, ringtone, full screen | tocar (toca, tocou) · o toque · a tela cheia | |
| incoming / missed / ongoing call | chamada recebida / perdida / em andamento | "Missed call from {name}" → «Chamada perdida de {name}». |
| Accept / Decline | Aceitar / Recusar | Also for invites and requests. |
| hang up, End call | Encerrar chamada / encerrar | |
| join (a call) | Entrar / entrar na chamada | |
| speaker, mute, unmute | o alto-falante · Silenciar · Ativar som | "Muted" → «Silenciado». |
| camera, microphone | a câmera · o microfone | "Switch camera" → «Trocar câmera». |
| connection, connecting, reconnecting | a conexão · Conectando… · Reconectando… | "Weak connection" → «Conexão fraca». |
| picture-in-picture, minimize | picture-in-picture · Minimizar | |

### 1.5 Security and encryption

| English | pt-BR | Notes |
|---|---|---|
| encryption, encrypted, decrypt | a criptografia · criptografado · descriptografar | |
| end-to-end encrypted | com criptografia de ponta a ponta | E2E stays E2E. |
| confirm (a person) | Confirmar / confirmar | Zuno's word for checking a person. "Confirmed people only" → «Só pessoas confirmadas». |
| approve (own device) | Aprovar / aprovar | Only for your own devices. Never mix with confirm. |
| verify, verification | verificar · a verificação | Only where the English says verify. |
| security details | os dados de segurança | |
| key, room keys | a chave · as chaves das salas | |
| backup, key backup, restore | o backup · o backup de chaves · restaurar | |
| security key, security phrase, recovery key | a chave de segurança · a frase de segurança · a chave de recuperação | Advanced screens only; never the 12-word code. |
| cross-signing, secret storage | a assinatura cruzada · o armazenamento secreto | |
| session (Advanced only) | a sessão | Only where the English says "session". |
| unlock, trust | desbloquear · confiar | |
| scan, QR code, code | Escanear · o código QR · o código | A bare «código» is never a password. |
| screenshot, screen recording, screen sharing | a captura de tela · a gravação de tela · o compartilhamento de tela | |
| block | Bloquear / desbloquear | Never for ban. |
| rooted device, compromised device | dispositivo com root · dispositivo comprometido | |
| clipboard, password manager | a área de transferência · o gerenciador de senhas | |
| incognito keyboard | Teclado anônimo | |

### 1.6 Account, server and membership

| English | pt-BR | Notes |
|---|---|---|
| account, password | a conta · a senha | "Wrong password." → «Senha incorreta.» |
| username, display name | o nome de usuário · o nome de exibição | |
| profile, profile photo | o perfil · a foto do perfil | One term for photo, picture and avatar. |
| email address | o endereço de e-mail | |
| invite | Convidar · o convite | The "Invited" badge → «Convite enviado»: a participle would force a gender (§2.5). |
| join (a room or community) | Entrar / entrar | "{target} joined" → «{target} entrou». |
| request, ask to join | o pedido · Pedir para entrar | "Let in" → «Aceitar». "Withdraw" → «Cancelar pedido». |
| leave | Sair / sair (saiu) | |
| remove (a person or item) | Remover / remover | The kick action. |
| ban | Banir / remover banimento | "Banned" heading → «Banidos». |
| report | Denunciar · a denúncia | Reasons: «Assédio», «Conteúdo ilegal», «Spam», «Outro motivo». |
| public / private | pública / privada | Feminine, agreeing with sala and comunidade. |
| topic, description, address, ID | o tópico · a descrição · o endereço · o ID | |

### 1.7 Roles and permissions

| English | pt-BR | Notes |
|---|---|---|
| admin, moderator, owner | administrador · moderador · proprietário | Role badges, generic masculine. |
| role, member, read-only | a função · Membro · Somente leitura | |
| permission (room or OS), access | a permissão · o acesso | |

### 1.8 Notifications and push

| English | pt-BR | Notes |
|---|---|---|
| notification, test notification | a notificação · a notificação de teste | |
| push, push target, push key | o push · o destino de push · a chave de push | "push notifications" → «notificações push». |
| registration (push) | o registro / registrar | Never «cadastro». |
| delivery, background sync | a entrega · a sincronização em segundo plano | |
| battery use: Unrestricted / Optimized / Restricted | uso da bateria: Sem restrições / Otimizado / Restrito | Android's labels, exactly. |
| Data Saver, Autostart | Economia de dados · Inicialização automática | |
| distributor, UnifiedPush, ntfy | o distribuidor · UnifiedPush · ntfy | |
| Google services / Google Play services | os serviços do Google / o Google Play Services | |
| Apple push | o push da Apple | |
| gateway, bridge, token | o gateway · a ponte · o token | |
| diagnostics | o Diagnóstico | |
| notification category, notification shade | a categoria de notificação · a aba de notificações | |
| lock screen | a tela de bloqueio | |
| quiet, sound, vibration | silenciosas · o som · a vibração | "Message tone" → «Som de mensagem». |

### 1.9 Location

| English | pt-BR | Notes |
|---|---|---|
| location, live location | a localização · a localização em tempo real | |
| share, start / stop sharing | Compartilhar · Iniciar / Parar compartilhamento | Also for sharing files. |
| Location Services, Privacy & Security (iOS) | Serviços de Localização · Privacidade e Segurança | iOS labels. |
| approximate, maps app | aproximada · o app de mapas | |

### 1.10 Settings, storage and data

| English | pt-BR | Notes |
|---|---|---|
| Settings | as Configurações | Zuno's and Android's. The iOS Settings app is «Ajustes» (§2.9). |
| storage, data, cache | o armazenamento · os dados · o cache | "Clear cache" → «Limpar cache». |
| theme: Dark / Light / Follow system | Escuro / Claro / Padrão do sistema | |
| Appearance / About / Advanced, version | Aparência / Sobre / Avançado · a versão | |
| feedback, crash reports | o feedback · os relatórios de falhas | |
| donate, privacy, Privacy policy, Terms | doar · a privacidade · Política de privacidade · Termos | |
| app, home screen, shortcut | o app · a tela inicial · o atalho | |
| recent apps, app switcher | os apps recentes · o seletor de apps | |
| Open source licenses, Source code | Licenças de código aberto · Código-fonte | License names stay in English. |

### 1.11 Terms settled up front

| English | pt-BR | Notes |
|---|---|---|
| hostname | o nome do servidor | Never left in English. |
| Asking to join (admin heading over others' requests) | Pedidos para entrar | Not «Pedindo para entrar», which reads as the reader asking. "Asking to join {name}" → «Pedidos para entrar em “{name}”». |
| Ask to join (subtitle) / Asks to join | Pedem para entrar / Pede para entrar | The button stays «Pedir para entrar». |
| Let them ask (setting) | Permitir pedidos | Not a request the reader sends. |
| Joined (label on a public room) | Você participa | |
| N other(s) | {count} outra pessoa · {count} outras pessoas | |
| asleep (device) / suspended (app) | em repouso / suspenso | Keep the two apart. |
| Call rang / ringing | A chamada tocou / tocando | |
| Hidden message | a mensagem oculta | «secreta» reads as encrypted. |
| Secure backup (screen) | «Recuperação» | A legacy name for the Recovery screen: point to it by its title. |
| Welcome to Zuno | Boas-vindas ao Zuno | «Bem-vindo» would force a gender. |
| {name} is confirmed | Você confirmou {name} | A participle would agree with the person. |
| Signed in (devices heading) / signed out | Dispositivos conectados / desconectado | |
| Sign out of "{name}"? | Sair de “{name}”? | Follows «Sair de todos os outros dispositivos». |
| character(s) | o caractere · os caracteres | |
| link | o link | |
| build (app version) | a compilação | |
| Room / Community defaults | Padrões da sala / da comunidade | |
| View only | Somente visualização | Apart from «Somente leitura», the role. |
| check mark | a marca de seleção | |
| launcher | o app de tela inicial | |
| vouch for (own devices) | validar | |
| raw (security key) | bruta | |
| standby bucket | o grupo de espera | Android's raw bucket names (rare, restricted, never) stay as they are. |
| Poor connection | Conexão ruim | Apart from «Conexão fraca». |

### 1.12 UI actions

| English | pt-BR |
|---|---|
| Cancel / Save / Saved | Cancelar / Salvar / Salvo |
| Delete / Remove | Excluir / Remover |
| Copy / Copied / Share | Copiar / Copiado / Compartilhar |
| Send / Continue / Continue anyway | Enviar / Continuar / Continuar mesmo assim |
| Done / Retry / Try again | Concluído / Tentar novamente / Tentar novamente |
| Close / Dismiss / Open / Open settings | Fechar / Dispensar / Abrir / Abrir configurações |
| Turn on / Turn off · On / Off | Ativar / Desativar · Ativado / Desativado |
| Allow / Not now / Skip | Permitir / Agora não / Pular |
| Confirm / Approve | Confirmar / Aprovar |
| Create / Start / Get started | Criar / Iniciar / Começar |
| Edit / Change / Review | Editar / Alterar / Revisar |
| Back / Stop / Play | Voltar / Parar / Reproduzir |
| Read more / Show less | Ver mais / Ver menos |
| Mark as read / Unread | Marcar como lida / Não lidas |
| Refresh / Search / Start over | Atualizar / Pesquisar / Recomeçar |

### 1.13 Status words

| English | pt-BR |
|---|---|
| Loading… / Sending… / Waiting… | Carregando… / Enviando… / Aguardando… |
| Checking… / Searching… | Verificando… / Procurando… |
| Failed | Falhou |
| Not set / Unknown / None / Never | Não definido / Desconhecido / Nenhum / Nunca |
| Not available / Yes / No | Indisponível / Sim / Não |
| Just now / Today / Yesterday / Coming soon | Agora mesmo / Hoje / Ontem / Em breve |

---

## 2. Style rules

### 2.1 Register
- «você» throughout, usually left implicit: «Toque para tentar novamente», «Sua conta foi excluída». Never «tu», never «o senhor».
- "tap" → «toque», "type" → «digite», "enter" → «insira», "choose/pick" → «escolha», "pull down" → «puxe para baixo».

### 2.2 Buttons and body text

| Where | Form | Example |
|---|---|---|
| Buttons, menu items, tabs, tooltips, switches, row labels | Infinitive | «Excluir conta», «Salvar», «Ativar alto-falante» |
| Body text, hints, the next step in an error | Imperative (você) | «Toque para tentar novamente.» |
| Titles that name something | Noun | «Configurações da sala», «Seus dispositivos» |
| Titles that instruct | Imperative | «Salve seu código de recuperação» |
| Confirmation titles ("Delete X?") | Infinitive + «?» | «Excluir sua conta?» |
| Progress labels | Gerund + «…» | «Criando conta…» |
| Success snack bars | Participle, English period kept or left out | «Senha alterada», «Denúncia enviada» |

Buttons that answer a question stay statements: «Combinam», «Não combinam», «Sim, concluir», «Não, parar». First-person buttons stay first person: «Já tenho um código».

### 2.3 Case and punctuation
- Sentence case everywhere, as in the English. Weekday and month names are lowercase. Never all caps.
- No exclamation marks, no emoji. Keep «…» (one character) wherever the English has it.
- Quotes: “ ” wherever the English has quotes. The one technical value keeps straight escaped quotes: `notificationsUnknownFormat` (`\"{type}\"`). Room, topic, device names and recovery words take “ ”: `“{name}”`.
- When body text names a screen, row, option or button, use its exact Portuguese label in “ ”. «Configurações» alone needs none.
- Keep the English «·» separators, colons and end punctuation exactly.

### 2.4 How Zuno speaks
- Zuno never speaks as «nós» or «eu». Write «O Zuno…» or recast impersonally.
- «o Zuno», «o Android», «o iOS», «o Google», «a Apple».
- Name no other apps beyond those the English names (ntfy, Google, Apple, CarPlay).

### 2.5 Names and gender (critical)
`{name}`, `{sender}`, `{target}`, `{first}`, `{second}`, `{people}` are display names of unknown gender.
1. Never put an article before a name: no «o {name}», «da {name}».
2. Subject names go first, bare: «{name} saiu», «{target} entrou».
3. Short labels with a preposition are fine: «Com {name}», «Respondendo a {name}», «Chamada perdida de {name}».
4. Never use an adjective or participle that agrees with the person. Infinitives and verbs avoid it: «Bloquear {name}?», «{name} confirmou», «Você confirmou {name}». Where a noun is needed, use «a pessoa».
5. English "they" for one person → «a pessoa» or drop the subject: "once they join" → «quando a pessoa entrar».

### 2.6 Brand-voice moments

| Moment | Pattern |
|---|---|
| Error: what happened, then what to do | «Não foi possível enviar a mensagem. Verifique sua conexão e tente novamente.» |
| Fixed phrases | "Check your connection and try again." → «Verifique sua conexão e tente novamente.» · "Pull down to try again." → «Puxe para baixo para tentar novamente.» · "Too many attempts." → «Muitas tentativas.» · "Something went wrong." → «Algo deu errado.» |
| Irreversible | "Nobody can undo this." → always «Ninguém pode desfazer isso.» |
| Reassurance | Calm present tense, no alarm words. |
| Success | Flat participle, no «com sucesso». |

- Calm, plain, minimal. Portuguese runs about 20% longer than English: cut filler, never a limit, consequence or next step.
- No «Desculpe», «Infelizmente», superlatives or «100% seguro».

### 2.7 Numbers, dates and units
- Numbers, dates and times stay inside their placeholders; never hard-code a format.
- "{date} at {time}" → «{date} às {time}» · "Until {time}" → «Até {time}» · "{days} days ago" → «há {days} dias» · "{page} of {total}" → «{page} de {total}».
- h, min, s, km, m, B, KB, MB stay as they are, with the space before them. Keep «%» where it is.
- Technical values stay exactly: `chat.example.org`, `https://`, `a–z, 0–9`, `@`, `ID`, `CarPlay`, `E2E`.

### 2.8 Ordinals
`securityOrdinal` precedes «palavra» (feminine): `{n, select, 1{1ª} 2{2ª} 3{3ª} other{{n}ª}}`. `settingsRecoveryWordLabel` → «{position} palavra». `settingsRecoveryConfirmBody` → «Digite a {first} e a {second} palavras da sua cópia salva.»

### 2.9 Platform labels
- Name Android and iOS settings by that OS's pt-BR label. The iOS Settings app is **Ajustes**: "Settings → General → Language & Region" → «Ajustes → Geral → Idioma e Região»; "Settings → Apps → Zuno → Language" → «Ajustes → Apps → Zuno → Idioma».
- iOS notification settings: «Tela Bloqueada», «Central de Notificações», «Faixas», «Indicadores», «Sons», «Mostrar Pré-visualizações», «Resumo Agendado», «Alertas Críticos», «Notificações Urgentes», «Anunciar Notificações».
- «iPhone» and «Android» as written. "your device" → «seu dispositivo», never «seu celular».

---

## 3. ICU and placeholder rules (the build breaks otherwise)

- Copy every `{placeholder}` exactly. Never translate, rename, add or drop one; you may move it. A string made only of placeholders and symbols stays byte-identical (`{count}`, `{name} · {time}`, `{label}: {count}`, `{size} MB`, `CarPlay`, `UnifiedPush`).
- **Plurals:** keep structure and selector name. Use only `one` and `other`. CLDR puts **0 and 1** in pt-BR's `one`, so the `one` text must read right for both: always write the number as `{count}`, never «uma» or «1».
  - Add a `one` case where the English has only `other` but Portuguese needs a singular: `matrixInvitePeopleInvited`, `matrixInviteWaitingForPeople`, `matrixSignupPasswordTooLong`, `securityPasswordTooShort`, `securityPasswordEmptyAdvice`, `settingsRecoveryCodeHint`, `settingsRecoveryRevealTitle`, `settingsRecoveryTooManyWords`, `roomInfoConfirmedCount`, and the `matrixRoomExitCommunityRooms*` family (both `count` and nested `orphaned`).
  - No `one` needed (same text for every number): `ageHours`, `ageMinutes`, `pushDelayHours`, `pushDelayMinutes`, `pushDelaySeconds`, `chatDeleteAllCount`, `chatSaveAll`, `chatShareAll`, `roomInfoMembersCount`, `notificationsMoreChatsAndRooms`.
  - Never add `zero`, `two`, `few`, `many` or `=n`; never use `#`. Every plural keeps `other`. Nested plurals keep their nesting.
- **Selects** (`notificationsFailureAutoSelected`, `pushSummaryPriority`, `pushSummaryStandbyBucket`, `securityOrdinal`): keep every case key; translate only the text; never drop `other`.
- **JSON:** apostrophes are literal. Escape `"` as `\"`. Put `\n` only where the English has it.
- **Native strings** (`x-native`): plain English stays plain; the three native plurals (`notificationsMoreChats`, `notificationsMoreRooms`, `notificationsMoreChatsAndRooms`) stay whole-message plurals. The five `x-ios-infoplist` keys have no placeholders and start with «O Zuno…». Notification strings are the shortest text: keep them short.
- `languageNativeName` → «Português (Brasil)».

---

## 4. Worked examples

| Key | English | pt-BR |
|---|---|---|
| `settingsDeleteAccountWarningTitle` | Delete your account? | Excluir sua conta? |
| `feedbackNotSent` | Feedback not sent. Check your connection and try again. | Feedback não enviado. Verifique sua conexão e tente novamente. |
| `chatNotSentRetry` | Not sent · Tap to retry | Não enviada · Toque para tentar novamente |
| `callsFailureOnAnotherDevice` | You are in this call on another device. Hang up there to join here. | Você está nesta chamada em outro dispositivo. Encerre lá para entrar aqui. |
| `settingsAccountPasswordChanged` | Password changed | Senha alterada |
| `blockingTitle` | Block {name}? | Bloquear {name}? |
| `matrixStateNameChanged` | `{sender} changed the room name to \"{name}\"` | `{sender} mudou o nome da sala para “{name}”` |
| `chatDeleteTitle` | `{count, plural, one{Delete message?} other{Delete {count} items?}}` | `{count, plural, one{Excluir mensagem?} other{Excluir {count} itens?}}` |
| `matrixInvitePeopleInvited` | `{count, plural, other{{count} people invited}}` | `{count, plural, one{{count} pessoa convidada} other{{count} pessoas convidadas}}` |
| `permissionsPhotoLibraryAddUsage` | Zuno saves photos and videos to your library only when you tap Save. | O Zuno salva fotos e vídeos na sua galeria só quando você toca em “Salvar”. |
