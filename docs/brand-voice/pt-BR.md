# Brand voice: Brazilian Portuguese (pt-BR)

Brazilian Portuguese for `lib/l10n/app_pt.arb`, the base Portuguese file, written for Brazil. The rules all languages share are in `translating.md`; this guide holds only what is Brazilian Portuguese. European Portuguese has its own guide (`pt-PT.md`); never mix the two.

**Binding, set by the product owner:**
- Address the reader as **você**: «Toque», «Digite», «Escolha», possessive «seu/sua».
- Chat = **conversa**, room = **sala**, community = **comunidade**. Never «grupo».
- **Zuno** is masculine and takes the article: «o Zuno», «do Zuno», and a sentence opens «O Zuno…» (the five `permissions*Usage` keys too). Likewise «o Android», «o iOS», «o Google», «a Apple».
- `languageNativeName` → «Português (Brasil)».

---

## 1. Glossary

### 1.1 Brand-voice words

| English | pt-BR | Notes |
|---|---|---|
| chat (one-to-one) | a conversa · as conversas | "New chat" → «Nova conversa». The "Chats" tab → «Conversas». Never «chat» or «bate-papo». |
| room (group chat) | a sala · as salas | Never «canal». |
| community | a comunidade | Never «espaço» or «servidor». |
| "Group with {names}" | «Conversa com {names}» | |
| device | o dispositivo | "your device" → «seu dispositivo». Never «celular» or «sessão». |
| recovery code | o código de recuperação | Never «chave» or «senha». |
| recovery | a recuperação | "Set up recovery" → «Configurar recuperação». |
| sign in | Entrar / entrar (entre, entrou) · o login | "New sign-in" → «Novo login». A signed-in device → «dispositivo conectado» (or «onde você entrou»). |
| sign out | Sair / sair (saia, saiu) | "Sign out everywhere else" → «Sair de todos os outros dispositivos». |
| sign up, sign-up code | Criar conta · o cadastro · o código de cadastro | |
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
| emoji, verification emoji | o emoji · as imagens | |

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
| mute (someone in a call) | Silenciar / silenciar | "{name} muted you" → «{name} silenciou você». "{name} was not muted." → «Não foi possível silenciar {name}.» |
| remove from the call | Remover da chamada / remover da chamada | "{name} removed you from the call." → «{name} removeu você da chamada.» "You were removed from this call." → «Removeram você desta chamada.», since «removido» would force a gender. "rejoin" → «entrar de novo». |
| camera, microphone | a câmera · o microfone | "Switch camera" → «Trocar câmera». |
| connection, connecting, reconnecting | a conexão · Conectando… · Reconectando… | "Weak connection" → «Conexão fraca». "Poor connection" → «Conexão ruim». |
| picture-in-picture, minimize | picture-in-picture · Minimizar | |

### 1.5 Security and encryption

| English | pt-BR | Notes |
|---|---|---|
| encryption, encrypted, decrypt | a criptografia · criptografado · descriptografar | |
| end-to-end encrypted | com criptografia de ponta a ponta | |
| confirm (a person) | Confirmar / confirmar | "Confirmed people only" → «Só pessoas confirmadas». |
| approve (own device) | Aprovar / aprovar | |
| verify, verification | verificar · a verificação | |
| security details | os dados de segurança | |
| key, room keys | a chave · as chaves das salas | |
| backup, key backup, restore | o backup · o backup de chaves · restaurar | |
| security key, security phrase, recovery key | a chave de segurança · a frase de segurança · a chave de recuperação | |
| cross-signing, secret storage | a assinatura cruzada · o armazenamento secreto | |
| session | a sessão | |
| unlock, trust | desbloquear · confiar | |
| scan, QR code, code | Escanear · o código QR · o código | A bare «código» is never a password. |
| screenshot, screen recording, screen sharing | a captura de tela · a gravação de tela · o compartilhamento de tela | |
| block | Bloquear / desbloquear | |
| rooted device, compromised device | dispositivo com root · dispositivo comprometido | |
| clipboard, password manager | a área de transferência · o gerenciador de senhas | |
| incognito keyboard | Teclado anônimo | |
| raw (security key), vouch for (own devices) | bruta · validar | |

### 1.6 Account, server and membership

| English | pt-BR | Notes |
|---|---|---|
| account, password | a conta · a senha | "Wrong password." → «Senha incorreta.» |
| username, display name | o nome de usuário · o nome de exibição | |
| profile, profile photo | o perfil · a foto do perfil | |
| email address | o endereço de e-mail | |
| invite | Convidar · o convite | The "Invited" badge → «Convite enviado». |
| withdraw (an invitation) | cancelar o convite | "{sender} withdrew your invitation" → «{sender} cancelou seu convite». |
| join (a room or community) | Entrar / entrar | "{people} joined" → «{people} entrou». |
| request, ask to join | o pedido · Pedir para entrar | "Let in" → «Aceitar». "Withdraw" → «Cancelar pedido». |
| leave | Sair / sair (saiu) | |
| remove (a person or item) | Remover / remover | The kick action. |
| ban | Banir / remover banimento | "Banned" heading → «Banidos». |
| report | Denunciar · a denúncia | Reasons: «Assédio», «Conteúdo ilegal», «Spam», «Outro motivo». |
| public / private | pública / privada | Feminine, agreeing with sala and comunidade. |
| topic, description, address, ID | o tópico · a descrição · o endereço · o ID | |
| hostname | o nome do servidor | |

### 1.7 Roles and permissions

| English | pt-BR | Notes |
|---|---|---|
| admin, moderator, owner | administrador · moderador · proprietário | Role badges, generic masculine. |
| role, member, read-only, view only | a função · Membro · Somente leitura · Somente visualização | |
| permission (room or OS), access | a permissão · o acesso | |

### 1.8 Notifications and push

| English | pt-BR | Notes |
|---|---|---|
| notification, test notification | a notificação · a notificação de teste | |
| alert | o alerta | "Security alerts" → «Alertas de segurança». |
| push, push target, push key | o push · o destino de push · a chave de push | "push notifications" → «notificações push». |
| registration (push) | o registro / registrar | Never «cadastro». |
| delivery, background sync | a entrega · a sincronização em segundo plano | |
| battery use: Unrestricted / Optimized / Restricted | uso da bateria: Sem restrições / Otimizado / Restrito | Android's labels. |
| Data Saver, Autostart | Economia de dados · Inicialização automática | |
| distributor | o distribuidor | |
| Google services / Google Play services | os serviços do Google / o Google Play Services | |
| Apple push | o push da Apple | |
| gateway, bridge, token | o gateway · a ponte · o token | |
| diagnostics | o Diagnóstico | |
| notification category, notification shade | a categoria de notificação · a aba de notificações | |
| lock screen | a tela de bloqueio | |
| quiet, sound, vibration | silenciosas · o som · a vibração | "Message tone" → «Som de mensagem». |
| standby bucket | o grupo de espera | |

### 1.9 Location

| English | pt-BR | Notes |
|---|---|---|
| location, live location | a localização · a localização em tempo real | |
| share, start / stop sharing | Compartilhar · Iniciar / Parar compartilhamento | Also for sharing files. |
| approximate, maps app | aproximada · o app de mapas | |

### 1.10 Settings, storage and data

| English | pt-BR | Notes |
|---|---|---|
| Settings | as Configurações | Zuno's and Android's. The iOS Settings app is «Ajustes» (§2.8). |
| storage, data, cache | o armazenamento · os dados · o cache | "Clear cache" → «Limpar cache». |
| theme: Dark / Light / Follow system | Escuro / Claro / Padrão do sistema | |
| Appearance / About / Advanced, version, build | Aparência / Sobre / Avançado · a versão · a compilação | |
| feedback, crash reports | o feedback · os relatórios de falhas | |
| donate, privacy, Privacy policy, Terms | doar · a privacidade · Política de privacidade · Termos | |
| app, home screen, shortcut, launcher | o app · a tela inicial · o atalho · o app de tela inicial | |
| recent apps, app switcher | os apps recentes · o seletor de apps | |
| Open source licenses, Source code | Licenças de código aberto · Código-fonte | |

### 1.11 Settled phrases

| English | pt-BR | Notes |
|---|---|---|
| Asking to join (admin heading) | Pedidos para entrar | Never «Pedindo para entrar». "Asking to join {name}" → «Pedidos para entrar em “{name}”». |
| Ask to join (subtitle) / Asks to join | Pedem para entrar / Pede para entrar | The button stays «Pedir para entrar». |
| Let them ask (setting) | Permitir pedidos | |
| Joined (label on a public room) | Você participa | |
| N other(s) | {count} outra pessoa · {count} outras pessoas | |
| asleep (device) / suspended (app) | em repouso / suspenso | |
| Call rang / ringing | A chamada tocou / tocando | |
| Hidden message | a mensagem oculta | Never «secreta». |
| Secure backup (screen) | «Recuperação» | |
| Welcome to Zuno | Boas-vindas ao Zuno | «Bem-vindo» would force a gender. |
| {name} is confirmed | Você confirmou {name} | |
| Signed in (devices heading) / signed out | Dispositivos conectados / desconectado | |
| Sign out of "{name}"? | Sair de “{name}”? | Follows «Sair de todos os outros dispositivos». |
| Room / Community defaults | Padrões da sala / da comunidade | |
| Make {people} an admin / You are now an admin (room updates) | {sender} deu a função “Administrador” para {people} / Agora você tem a função “Administrador” | Every role the same way, with its exact label. |
| character(s), link, check mark | o caractere (os caracteres) · o link · a marca de seleção | |

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

## 2. Brazilian Portuguese rules

### 2.1 Register
- «você» throughout, usually left implicit: «Toque para tentar novamente», «Sua conta foi excluída». Never «tu», never «o senhor».
- "tap" → «toque», "type" → «digite», "enter" → «insira», "choose/pick" → «escolha», "pull down" → «puxe para baixo».

### 2.2 Forms

| Where | Form | Example |
|---|---|---|
| Buttons, menu items, tabs, tooltips, switches, row labels | Infinitive | «Excluir conta», «Salvar», «Ativar alto-falante» |
| Body text, hints, the next step in an error | Imperative (você) | «Toque para tentar novamente.» |
| Titles that name something | Noun | «Configurações da sala», «Seus dispositivos» |
| Titles that instruct | Imperative | «Salve seu código de recuperação» |
| Confirmation titles ("Delete X?") | Infinitive + «?» | «Excluir sua conta?» |
| Progress labels | Gerund + «…» | «Criando conta…» |
| Success snack bars | Participle, English period kept or left out | «Senha alterada», «Denúncia enviada» |

Statement and first-person buttons: «Combinam», «Não combinam», «Sim, concluir», «Não, parar», «Já tenho um código».

### 2.3 Typography
- Quotes: “ ”, as in `“{name}”`.
- Colons keep the English spacing.
- Weekday and month names are lowercase.

### 2.4 Names
- No article before a name: never «o {name}» or «da {name}».
- Subject names go first, bare: «{name} saiu», «{people} entrou».
- Short labels: «Com {name}», «Respondendo a {name}», «Chamada perdida de {name}».
- Verbs avoid agreement: «Bloquear {name}?», «{name} confirmou», «Você confirmou {name}». Where a noun is needed, «a pessoa».
- "they" → «a pessoa» or drop the subject: "once they join" → «quando a pessoa entrar».

### 2.5 Fixed phrases
- Error pattern: «Não foi possível enviar a mensagem. Verifique sua conexão e tente novamente.»
- "Check your connection and try again." → «Verifique sua conexão e tente novamente.»
- "Pull down to try again." → «Puxe para baixo para tentar novamente.»
- "Too many attempts." → «Muitas tentativas.» · "Something went wrong." → «Algo deu errado.»
- "Nobody can undo this." → always «Ninguém pode desfazer isso.»
- Never «Desculpe», «Infelizmente», «com sucesso» or «100% seguro».

### 2.6 Numbers, dates and units
- "{date} at {time}" → «{date} às {time}» · "Until {time}" → «Até {time}» · "{days} days ago" → «há {days} dias» · "{page} of {total}" → «{page} de {total}».
- Brazilian `one` covers 0 and 1, so its text must read right for both: the number is always `{count}`, never «uma» or «1».

### 2.7 Ordinals
`securityOrdinal` precedes «palavra» (feminine): `{n, select, 1{1ª} 2{2ª} 3{3ª} other{{n}ª}}`. `settingsRecoveryWordLabel` → «{position} palavra». `settingsRecoveryConfirmBody` → «Digite a {first} e a {second} palavras da sua cópia salva.»

### 2.8 Platform labels
- Android Settings is **Configurações**; the iOS Settings app is **Ajustes**: "Settings → General → Language & Region" → «Ajustes → Geral → Idioma e Região»; "Settings → Apps → Zuno → Language" → «Ajustes → Apps → Zuno → Idioma».
- iOS: «Serviços de Localização», «Privacidade e Segurança», «Tela Bloqueada», «Central de Notificações», «Faixas», «Indicadores», «Sons», «Mostrar Pré-visualizações», «Resumo Agendado», «Alertas Críticos», «Notificações Urgentes», «Anunciar Notificações».

---

## 3. Worked examples

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
