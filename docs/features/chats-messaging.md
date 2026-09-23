# Chats & Messaging

## Overview

The chat timeline is the core surface of the app: message bubbles, sending
(text/media/voice), event rendering, media galleries, and the room-page
scroll/pagination behavior. It has no repository layer — `RoomPage` reads
and mutates the `matrix` SDK's `Room`/`Timeline`/`Event` objects directly
(see CLAUDE.md's architecture map). This doc covers everything that decides
what a message looks like, how it's sent, and how the timeline behaves.

## Architecture

- **`RoomPage`** (`lib/features/chat/presentation/room_page.dart`) holds
  state and logic only: the live `Timeline`, read markers, pagination,
  sending, recording, typing notices, menus. Every widget lives beside it:
  `message_list_view.dart` (list, memo, day labels, end rows),
  `message_tile.dart` (one row), `message_bubble.dart` (shape, colors),
  `message_meta.dart` (time row), `message_contents/` (text, media, voice,
  file, call, quote, reactions, upload tile), `room_app_bar.dart`,
  `message_composer.dart`, `message_actions_sheet.dart`. Pure helpers and
  shared types are in `lib/features/chat/data/`.
- **A message rebuilds only when it changes.** `messageRowDataFor` builds a
  value-equal `MessageRowData` per visible message and `RowMemo`
  (`core/ui/row_memo.dart`, capped at 160) returns the identical row widget
  when the record is equal, so Flutter skips that subtree. The record holds
  everything the look depends on, including what a row merely points at
  (the quoted message's type and sender name). A stale record means a stale
  message: anything new that changes how a message looks joins the record,
  with a test. The memo is cleared when the `Timeline` instance changes.
- **The page is quiet.** It rebuilds for room-state bursts (coalesced per
  microtask), timeline updates and syncs that mention this room
  (`syncTouchesRoom`); any sync also counts while the active-call banner
  shows, because that banner expires by time. Recording seconds, upload
  progress and the scroll-to-latest toggle are `ValueNotifier`s read by
  their own small widgets.
- **Opening**: the first frame is header, wallpaper and composer. The
  timeline loads at once from the local database but is applied when the
  route animation completes; the first read marker and history request
  follow the apply. The spinner shows only if the slide has finished and the
  timeline has not.
- **Reply targets**: a quote whose original is not in the timeline asks
  `ReplyTargetCache` once per event ID per page, from `initState`, never
  from `build`; "not available" is remembered and "Reload messages" renews
  the cache.
- **`event_display.dart`** is the single source of truth for "what is this
  event, and should it be shown at all" — see Key Design Decisions below.
  Every other surface that used to independently guess at this (room list
  preview, notification body, reply quote snippet, timeline visibility
  filter, sender-grouping, read-marker logic) now calls into it.
- **Mentions** are four small units: `mention_query.dart` (pure: is a
  mention being typed at the cursor, matching, insert text),
  `mention_suggestions.dart` (the picker under the compose bar),
  `core/matrix/mention_fragments.dart` (which `@fragments` an event's
  `m.mentions` declares) and `core/matrix/mention_only_html.dart` (does a
  formatted body carry anything beyond text and mention pills). See Key
  Design Decisions.
- **`message_html_style.dart`** is the one style map for `flutter_html`
  bubbles (links: `linkColor`, no underline); `widget_memo.dart` is the
  LRU identity cache that keeps `flutter_html` from re-running its styling
  pass on every sync tick.
- Tapping the app bar title (name + access line) opens `RoomInfoPage`; the
  overflow menu entry stays.
- **`media_gallery_group.dart`** groups multiple media events sent together
  into one timeline tile; `gallery_viewer_page.dart` is the full-screen
  pager for it.
- **Attachment caching**: `AttachmentCache` (in-memory) plus
  `DiskAttachmentCache` (disk-backed) form a two-tier cache for
  message attachments, via a shared `fetchCachedAttachment`
  helper (memory → disk → network, populating both tiers on the way back).
  Concurrent fetches of one key share a single pending future, so N
  widgets missing the cache together make one request.
- **Avatars**: `MxcAvatar` renders `MxcAvatarImage`, an `ImageProvider`
  equal on (`mxc`, bucket), through the `Image` widget. Two buckets only:
  `small` (96 crop) up to 56 px across, `large` (320 scale) above, so a
  person costs one request per bucket however many sizes show them.
  Flutter's image cache holds the decoded picture (no flicker on rebuild);
  bytes go through `fetchCachedAvatar`: disk only, never expiring, write
  awaited. The initial shows until the first frame or on error, sized to
  the avatar, on one of eight tones picked by a folded FNV-1a hash of
  `toneSeed` (pinned by tests: changing it recolors everyone). Seed with a
  stable Matrix ID where one exists, so a rename keeps the color.
  Videos and files use `fetchCachedAttachmentFile` instead: disk tier
  only, returning the cached file itself, so share, save and the video
  viewer never re-download or hold a large file in memory. One key per
  event (`attachmentCacheKey`) across every consumer. The SDK's own file
  store is off (`maxFileSize` 0), so this is the only cache there is.
- **Media send pipeline is app-side and native**; the SDK's image shrink
  is bypassed. `image_send_preparation.dart` / `video_send_preparation.dart`
  build the final `MatrixImageFile`/`MatrixVideoFile`, thumbnail and
  blurhash, then call `sendFileEvent` with `thumbnail:` set and no
  `shrinkImageMaxDimension`. Native side: `ImageResizer.kt` (channel
  `zuno/image`) and `VideoTools.kt` (`zuno/video`: probe, remux,
  thumbnail), each on its own background thread.
- **Attachment send flow**: one progress bar per attachment covers
  compression (first half) and upload (second half) via
  `combinedSendProgress` (`send_progress.dart`). A synthetic pending tile
  (`_PendingAttachmentTile`) stands in before the real timeline row exists
  (matched later by `txid`); once it lands, the real row keeps drawing the
  preview bytes until the upload finishes. The whole send, batch loops
  included, holds `UploadForegroundService` (a dataSync foreground service
  with a progress notification) so backgrounding can't freeze or kill it.
- **Inbound share (Android share sheet)**: `ShareActivity.kt` (no UI, owns
  the `SEND`/`SEND_MULTIPLE` filters) forwards to `MainActivity` with a
  read grant. `MainActivity` hands the payload to Dart over `zuno/share`
  (`lib/core/share/inbound_share.dart`, same shape as the shortcut
  channel: a stream while running, a one-shot take on cold start).
  `_AuthGate` pushes `SharePickerPage` (joined chats, search), which
  replaces itself with `RoomPage(pendingShare:)`. `RoomPage` prefills text
  into the composer and sends files through `_sendPickedMedia` (the
  gallery picker's dispatch) or `_sendFile`. Files are copied into
  `cacheDir/shared/<uuid>/<i>/<name>` by `MainActivity` off the main
  thread only after a chat is picked, and deleted when the send ends.

## Data & State

- **No separate message/timeline model** — SDK `Event`/`Timeline`/`Room`
  objects are the state; `RoomPage` derives UI state (grouping, date
  dividers, gallery membership) from a plain pass over the newest-first
  event list on each build.
- **`MessageKind`** (`event_display.dart`) is the exhaustive, no-`default`
  enum every consumer switches on: text, photo, video, voice, file,
  location, callSummary, deleted, undecryptable, nonMessage,
  hiddenSignaling. Adding a
  new kind is a compile error everywhere it isn't handled, not a bug
  reported later.
- **Gallery wire format**: each item stays a normal `m.image`/`m.video`
  event, with `im.zuno.gallery: {id, index, count}` added to its content —
  not one fat multi-file event. This means every other Matrix client still
  sees N normal messages (forward/redact/download all keep working with no
  new code), and an unrecognized shape (`galleryGroupOf` returns null)
  degrades to an ordinary single-photo render rather than breaking the tile.
  Grouping itself (`groupGalleries`) happens client-side, one pass over the
  timeline list: the anchor is always the group's newest surviving member,
  so every existing per-index pass (read ticks, date dividers, sender
  grouping) keeps working unmodified on plain indices.
- **Reactions**: `m.reaction`/`m.annotation`, aggregated per emoji key. This
  app enforces one reaction per user per message (client-side convention,
  not a Matrix constraint) — picking a new emoji replaces the old one.
- **Read receipts / unread count**: `canCarryReadMarker` is simply
  `event.status.isSent` — see Key Design Decisions for why no
  content-based filter works here.
- **Persistent media cache**: disk tier keeps bytes in the app's cache
  directory. Message attachments expire after a day (sliding), so
  decrypted media does not linger. Avatar entries never expire: an `mxc`
  address is immutable and a new avatar is a new address; the 256 MB
  oldest-first sweep bounds them. Because of that, avatar bytes that fail
  to decode are deleted, or one bad response would break that avatar for
  good; failed loads are also evicted from the image cache so they retry.
  "Clear media cache" in Settings clears both tiers, Flutter's image cache
  and the map tile cache (`location-sharing.md`). Expiry
  deletes are fire-and-forget and ignore their own failure: two readers can
  meet the same stale entry and both try to delete it, and the loser would
  otherwise raise `PathNotFoundException` from an unawaited future, where
  nothing can catch it.
- **Chat wallpaper** is one fixed image, the same in every conversation,
  with nothing for the person to choose (`chat_wallpaper.dart`).
  `assets/wallpaper/chat_tile.png` is a 480 px doodle tile, white on
  transparent, shipped at 1x, 2x and 3x. It is drawn once behind the
  messages: repeated at its own size (`BoxFit.none`, top left), tinted
  with `onSurface` at 5% through `BlendMode.srcIn` so one file serves both
  themes, `FilterQuality.low`, inside its own `RepaintBoundary`. A few
  textured rectangles per frame, where a painted pattern cost one draw
  call per dot. The decoded 3x tile is about 8 MB, held once in the image
  cache. `ChatListView` preloads it after its first frame
  (`precacheChatWallpaper`), so it neither pops in nor decodes during the
  slide into a chat.

## Communication

- Sending goes straight through SDK methods (`room.sendTextEvent`,
  `room.sendFileEvent`, ...) — no wrapping service layer.
- **Text goes out as typed.** Every `sendTextEvent` call (composer,
  notification reply) passes `parseMarkdown: false, parseCommands: false`;
  the SDK has no client-wide switch, so a new call site must pass both.
  Commands off is a safety rule, not just a side effect: the SDK's set
  includes `/leave`, `/logout`, `/ban`, `/clearcache`, which a message
  starting with that word would otherwise run.
- **Upload progress**: `matrix_api_lite`'s `uploadContent` has no
  progress hook and sends the whole body as one `http.Request`; this app's
  `UploadProgressHttpClient` wraps the client and slices the body into fixed
  64KB pieces itself to get real intermediate progress values (a naive
  stream transform over the SDK's own request only ever reports one chunk —
  the whole file).
- **Media processing never falls back to the original bytes**: an
  undecodable photo or a failed video encode throws
  `MediaProcessingException` and the send is refused with a short message,
  since sending the untouched file would leak metadata. A server-side
  `FileTooBigMatrixException` is terminal too (no retry record). Every
  failed media send discards the SDK's own error placeholder
  (`discardSendPlaceholder`), because the app tracks failures itself.
- **A refused text send shows "Not sent · Tap to retry"** (`not_sent.dart`).
  `isNotSent` is an own event in `EventStatus.error` — what the SDK leaves
  behind both when `sendTextEvent` throws (`M_FORBIDDEN`, too large) and
  when it gives up silently: a 429 that outlasts the one-minute
  `retry_after_ms` loop returns `null` with no exception. The bubble tap and
  the offline→online pass (`_retryAfterReconnect`) both call
  `Event.sendAgain()`; the reconnect pass scans the timeline for
  `notSentOwnEvents` instead of remembering transaction ids, which is what
  catches the silent case. A bubble dims only while `isSending`; an error
  bubble stays opaque with the red row. Media upload failures are tracked
  separately (`_failedSends`, above); a media *event* left in error status
  after its upload is resent the same way.
- **Photo send**: native resize to the long-edge cap (1080, or 720 with
  "Reduce media size", on by default) at JPEG quality 85 / 75, PNG stays
  PNG, orientation baked into pixels; an 800px thumbnail only when the main image is larger
  and the thumbnail actually smaller; blurhash from a 32px sample in an
  isolate. The picker no longer re-encodes (`imageQuality` unset), so the
  resizer is the single lossy step.
- **Video send plan** (`video_send_plan.dart`, pure): a native probe
  (dimensions, bitrate, codecs) picks remux vs re-encode. H.264 with AAC or
  no audio, within the cap and at or under the target bitrate plus 25%, is
  remuxed losslessly through `MediaMuxer`; anything else is re-encoded at a
  fixed bitrate by output size (2 Mbps for the 720 tier, 1 Mbps for 480),
  never above the source's own bitrate, never below 1 Mbps. The old
  source-fraction mode turned a 4K recording into a 14 Mbps file the server
  rejected. The thumbnail is taken from the source on a separate native
  thread while encoding runs and doubles as the pending tile's placeholder.
- **Privacy**: sent photos and videos carry no EXIF or location metadata
  (`Bitmap.compress` writes none; the remuxer and encoder write no location
  atom) and generic names (`photo.jpg`/`photo.png`/`video.mp4`), since
  original names carry timestamps. Files sent through the file picker stay
  byte-for-byte original by design.
- **Pagination**: `Timeline`'s own history-request mechanism, triggered on
  scroll-up, on initial load, and after every timeline update (not
  scroll-only — a room whose synced window filters down to fewer visible
  events than fill the screen has nothing to scroll, so a scroll-only
  trigger never fires). A "Start of conversation" marker replaces the
  loading spinner once `Timeline.canRequestHistory` goes false.
- **`roomPreviewLastEvents`** is narrowed at the client level
  (`createMatrixClient()`) to `{m.room.message, m.room.encrypted,
  m.sticker}` — the SDK's default set includes call-signaling event types
  this app never sends/renders, which could otherwise become a room's
  preview with no bubble behind them.
- **Reload messages** (room menu): wipes locally cached timeline
  (`client.database.deleteTimelineForRoom` + `room.lastEvent = null`, same
  calls the SDK's own gap-handling logic makes) and rebuilds `RoomPage`'s
  `Timeline`, forcing a re-paginate from the server. Purely local-cache
  reset, nothing server-side.

## Key Design Decisions

### The composer stops a recovery code leaving the device

Sending what looks like the recovery code opens a confirmation first
(`recovery_code_warning.dart`, detection in `security-verification.md`).
It warns rather than refuses: blocking outright would also block sending
the code to one's own notes, and people would retype it in pieces. The
check runs in `_confirmThenSend`, which is why the composer clears after
the await rather than in `_send`.

### One rule for what an event is (`event_display.dart`)

Event classification used to be duplicated across six call sites (room-list
preview, notification body, bubble rendering, timeline visibility filter,
sender-grouping, unread-correction), each hand-maintained — adding a new
msgtype (this app adds several: call summary, call ring/decline, voice
messages, galleries) was a fresh chance for one site to drift from the
others. Concretely this produced: call signaling leaking into room-list
previews, in-room verification strings leaking the same way, edits showing
their raw `* ` prefix in the room list while the timeline showed folded
text, and stickers (a distinct event *type*, not a msgtype) being excluded
from the timeline while still counted as previewable.

Fixed by collapsing all six into two pure, unit-tested functions:
`isDisplayableTimelineEvent(event, showHiddenMessages:)` (visibility) and
`summarize(event) → MessageSummary(kind, text, call)` (description). Every
consumer now calls one of these, notifications included.
`event_display_test.dart` is a table of ~22 event shapes with expected
visibility/kind/text for each — adding a new message shape means adding a
row, and the table is the enforcement mechanism, not just documentation.

Two related classification problems turned out **not** to be answerable by
the same rule:

- **Room-list preview of an edited last-event**: the SDK replaces
  `room.lastEvent` with the raw edit event, which the room list has no
  `Timeline` to fold via `getDisplayEvent` (unlike the in-room timeline).
  `isPreviewableLastEvent` asks what the event *resolves to* — rebuilding
  an `Event` from `m.new_content` so `plaintextBody`/`imageCaption`/
  `isVoiceMessage` keep working, not just reading fields out of the raw map.
- **Read-marker / unread count**: every room here is encrypted, so
  everything goes over the wire as `m.room.encrypted`, and the server's
  `.m.rule.encrypted` underride counts unread *before decryption*, from an
  envelope with no readable type. No filter over decrypted events can ever
  match what the server already decided — two prior attempts (mirroring
  `isDisplayableTimelineEvent`, then hand-adding exceptions) each just moved
  which hidden-but-server-counted event leaked through as a stuck badge.
  The fix: stop trying to guess content-based eligibility at all —
  `canCarryReadMarker` is `event.status.isSent`, full stop (excluding only a
  still-sending local echo, whose event ID can still change). Receipts are
  cumulative, so over-including is free; under-including leaves a badge
  that never clears.

**Takeaway for extension**: "what do we draw", "what can the room list
preview", and "what did the server count toward unread" are three distinct
questions in an encrypted room; a fix to one must not assume it also
answers the others.

### Bubble layout model

- Media, voice, file and location bubbles are a fixed 2/3 of the screen;
  everything else shrinks to its content under a 3/4 ceiling, with no
  floor. Corners are 20 px, tightened to 6 px where messages of one run
  meet on the sender's side (`bubbleRadius`); a run is one sender, no
  hidden event or day change between, at most five minutes apart.
- The time row (`MessageMeta`: "edited", time, clock/tick) is tucked into
  the last text line: the paragraph ends with a `WidgetSpan` holding an
  invisible twin of the row (`TuckedMeta`), and the visible row is
  `Positioned` bottom-right over it. If the twin does not fit, the paragraph
  wraps it and the row lands below the text. Voice, file, call and location
  draw the row in their own bottom line; captionless media overlays it on a
  dark chip; a collapsed long message shows it beside "Read more".
- `IntrinsicWidth` is used only when a bubble has a reply quote (the quote
  must stretch to the bubble). `flutter_html` bubbles never get it: they sit
  in a `SizedBox` as wide as the plain-text body (`estimateTextWidth()`,
  text scale applied), floored at a third of the screen because lists and
  headings render wider than their plain text; their time row stays below.
- File names keep their extension visible: `FileNameText`
  (`file_name_text.dart`) splits at the last dot and gives only the base an
  ellipsis. Dotfiles, names without a dot, and suffixes over ten characters
  are left whole.
- Long messages (>12 lines or >600 chars) collapse behind a "Read more"
  toggle — plain-text branch uses a real `maxLines`, HTML branch clips to a
  fixed height since `flutter_html` has no line-limit concept.

### Mentions ride on the event, never on a member list

- **Sending.** The picker inserts the SDK's own mention fragment
  (`User.mentionFragments.first`: `@Name`, or `@[Full Name]` when the
  name has spaces; `@username` only when no display name exists). Only
  that shape lets `sendTextEvent` resolve it and attach `m.mentions` —
  which is what earns the recipient a highlight push
  (`.m.rule.is_user_mention`). No `matrix.to` pill is written (markdown
  is off), so other clients show the fragment as plain text. Synapse sets
  new accounts' display name to the username, so this reads as
  `@username` on this server.
- **Picker cost model.** Candidates are the members sync already delivered
  (`getParticipants`). The full `/members` list is fetched at most once per
  room per session, joined members only, and only when at least two
  characters follow the `@` and `participantListComplete` is false. The
  fetch runs inside one `database.transaction` so thousands of member rows
  are one commit; the wrapped action never throws, because the SDK's
  transaction doesn't reset its batch on error. 30 rows, lazily built.
  Opening or reading a room loads nothing (`room_page_members_test.dart`).
- **Rendering.** Highlight comes from the event's `m.mentions` only
  (`mentionFragmentsOf`), bold in the primary colour, never tappable. A
  rendered mention never shows a server name: the plain path matches an
  optional `:domain` after the mention and draws only the part `m.mentions`
  vouches for, and a pill's text goes through `withoutServer`. The domain
  must look like one (a dot, optional port) so `@[Alice Smith]:hello` keeps
  its words, and an unvouched `@nobody:server` stays whole rather than being
  silently shortened. A
  formatted body that is nothing but text and pills is rendered through the
  plain `LinkifiedText` path (`isMentionOnlyHtml`), skipping `flutter_html`
  entirely; real HTML has its `matrix.to` user anchors rewritten to spans
  (`highlightUserMentionsInHtml`) and `onLinkTap` refuses `matrix.to`.
- **Mention detection** (`mentionQueryAt`): `@` at the start or after
  whitespace, followed by localpart characters (`matrixLocalpartChars` —
  the full Matrix set, not the narrower sign-up one, or a hyphenated member
  could never be picked), text before the cursor only. `foo@bar`, `@ `,
  `@bob!`, `@bob:server` never trigger.

### Gallery grouping over a single fat event

Explicitly rejected: a single multi-item event (invisible/unrenderable to
any other Matrix client, needs new send and render paths) and a
client-side-only "same sender within N seconds" heuristic (no wire change,
but grouping would differ per device and shift as history paginates). The
custom-content-key-on-ordinary-events approach was chosen specifically for
cross-client compatibility and graceful degradation.

### Inbound share: trampoline activity, copy after pick

`MainActivity` keeps the template's empty `taskAffinity`, so a `SEND` from
another app would start a second `MainActivity` and a second Flutter
engine inside the sender's task. `ShareActivity` forwards with
`NEW_TASK | SINGLE_TOP`, the path shortcuts and notification taps already
use, so the running engine gets `onNewIntent`. Plugins
(`receive_sharing_intent`, `share_handler`) were rejected: they put the
filters on `MainActivity` and want `singleTask`, which calls,
picture-in-picture and the lockscreen ring screen were tuned against.
Content is copied only after a chat is picked: no blank trampoline while
a large video copies, no I/O when the picker is cancelled. Shared text is
prefilled, never auto-sent. Not built: Direct Share targets in the system
sheet (additive, would reuse the pinned-shortcut code).

## Gotchas & Constraints

- **Never reload members from `client.onRoomState`.** `requestParticipants`
  emits one member-state event per member it caches, so such a listener
  re-enters itself in an unbroken microtask chain and starves the main
  isolate (ANR on device, hung test). Members are loaded on demand by the
  picker only.
- **The SDK resolves mentions by display name, not username.** A member
  with no display name has empty `mentionFragments`; mentioning them sends
  plain text with no `m.mentions` and no notification. Usernames with dots
  need the bracketed form, which `mentionInsertText` produces.
- **`flutter_html` re-runs its styling/tree pass on every build** even when
  the input string is unchanged (only the parse is skipped). Hence the
  per-event widget memo; theme changes still rebuild via the inherited
  dependency.
- **Shared file names are attacker-controlled**: `DISPLAY_NAME` comes from
  the sending app's provider. `InboundShareDecision.safeFileName` strips
  separators and rejects `.`/`..`, and the copy refuses a target outside
  its per-file directory. Keep both if the copy ever moves.
- **`Event.body`/`Event.plaintextBody`**: `Event.body` is the literal
  `body` field and can be empty or the SDK's raw `"Unknown message format of
  type ..."` fallback for any client-native-formatted (HTML) message
  without a plain fallback — never render `Event.body` directly in
  user-facing text (reply previews, room-list preview, compose reply/edit
  banner). Use `Event.plaintextBody`, which converts `formatted_body` when
  present and strips the raw `<mx-reply>` block.
- **Undecryptable events**: only `messageType == BadEncrypted` is a
  reliable in-timeline signal; an event that is still literally type
  `m.room.encrypted` with no such tag can be silently absent from the
  timeline while still eligible to become `room.lastEvent`. `
  isUndecryptableEvent` is the shared, broadened check — treat "can't
  decrypt" as "any still-`m.room.encrypted` event", not just the
  SDK-tagged case.
- **Decrypt-failure message text**: show one fixed, friendly string
  ("Message cannot be read on this device") rather than the SDK's raw exception
  text — the SDK's own `event_localizations.dart` only special-cases a
  handful of `DecryptException`s and falls back to the raw (sometimes
  cryptography-internal, e.g. vodozemac ratchet errors) message otherwise.
- **`room.lastEvent` changes identity, not just ID**: the SDK assigns a new
  `Event` instance for the sent echo and again for the synced copy, all
  with one event ID, and a redaction mutates only the current instance in
  place. Anything caching the last event (the chat list's
  `LastMessagePreview` keeps a decrypted copy) must follow the instance
  (`identical`), not the event ID, or a deleted message keeps its text.
- **Edits replace, not append**: the SDK replaces `room.lastEvent` with the
  edit event itself; anything reading "the newest message" outside the
  in-room `Timeline` (which folds edits via `getDisplayEvent`) must resolve
  the edit's `m.new_content` explicitly or it will show stale/raw text.
- **Pagination must not be scroll-only**: a room whose initial synced
  window filters down to fewer visible events than fill the screen has
  nothing to scroll, so a scroll-triggered-only pagination listener never
  fires. Trigger on load and on every timeline update too.
- **Rebuild storms from `onRoomState`**: the SDK's pagination pass touches
  `room.setState(dbUser)` once per not-yet-resolved sender, which can be
  dozens of events per pagination round in a multi-sender backlog room.
  Anything subscribed to `onRoomState` for rebuild purposes must coalesce
  bursts within a microtask into one rebuild, not one `setState` per event.
- **`IntrinsicWidth` + `stretch`**: a reply-quote/call-summary box that
  needs to fill the bubble's width needs `crossAxisAlignment: stretch` on
  the bubble's content column (plain `start` gives children loose,
  content-sized width regardless of the column's own resolved width).
  Never set an explicit `width: double.infinity` on a descendant of an
  `IntrinsicWidth` ancestor — its own intrinsic-width computation resolves
  to infinity and throws a layout assertion (rendered as a blank grey box
  with no visible error).
- **Rounded decoration + non-uniform border**: a `BoxDecoration` with
  `borderRadius` and a **non-uniform** `Border` (e.g. one accent-colored
  side) throws at paint time. Paint an accent edge as a separate
  `Positioned` strip in a `Stack` instead of a border side.
- **Legacy msgtype constants**: this app has renamed its custom msgtype
  namespace before (`im.luma.*` → `im.zuno.*`); any such rename needs every
  comparison site updated together or older events matching the old
  constant silently stop being recognized (lost icon/summary, or a
  previously-hidden signaling event starts rendering as an ordinary
  bubble). Compatibility shims for a retired namespace should eventually be
  removed once no such events remain relevant to support.
- **Non-message call event types**: the SDK's default
  `roomPreviewLastEvents` includes `m.call.*`/`com.famedly.call.member`
  types this app doesn't use (calls run on their own MatrixRTC-inspired
  layer) — leave `roomPreviewLastEvents` narrowed rather than widening it
  back to defaults.
- **Video encoder orientation**: a target width/height computed from the
  probe's rotation-corrected display size (or `video_player`'s, as the
  fallback) must be swapped back to
  raw sensor orientation before being handed to `light_compressor` (which
  applies its target to the pre-rotation raw frame buffer) — a portrait
  phone video is almost always a landscape sensor frame plus a rotation
  flag, not a native-portrait encode. Convert only at the compressor call
  site; everything else (attachment `w`/`h`, UI) stays in display
  orientation.
- **Pending-attachment thumbnails**: `Event._getCachedFile` returns null
  outright for a still-pending event's thumbnail (no fallback to the full
  file) — a still-sending image or video renders from the pending send's
  in-memory preview bytes (`Image.memory`), not a cache fetch; both the
  synthetic tile and the real sending row must honour those bytes, or the
  preview vanishes the moment the row lands. Without a frame, a video
  falls back to an aspect-ratio-correct box, not a spinner.
- **Foreground service starts are refused from the background on
  Android 12+**: `UploadForegroundService` is acquired once per send or
  batch (refcounted) while the app is visible and never stopped and
  restarted between items or between a file and its thumbnail. Android 15
  caps dataSync services at six hours a day, so the service honours
  `onTimeout`.
- **The wait for the slide is the shared `RouteSettled` mixin**
  (`app-foundation.md`); `RoomPage` applies the pending timeline in
  `onRouteSettled`.
- **A keyed lazy list needs `findChildIndexCallback`.** Without it a new
  message shifts every index and remounts every visible row, memo or not: a
  playing voice message stops and "Read more" collapses. Rows also keep one
  shape (`Column` keyed `row-<id>`, day label optional) so a row never
  changes depth.
- **`Text.rich` already scales its `WidgetSpan` children.** Text inside a
  span is scaled twice unless wrapped in `MediaQuery.withNoTextScaling`
  (the invisible time twin is).
- **`GestureDetector` hit-tests only its child by default.** `SwipeToReply`
  is `translucent`, so a swipe can start in the empty space beside a short
  bubble, as it could with `Dismissible`.
- **Links use `ZunoColors.link`**, in `LinkifiedText` and the HTML style
  map. A fixed light blue was unreadable on the light theme's bubbles.
- **The composer's send/mic swap is keyed on the button, not the icon.**
  `MessageComposer`'s `AnimatedSwitcher` only switches between
  `ValueKey('send')` and `ValueKey('mic')`. The mic `Listener` keeps its
  key for the whole recording (even when tap-to-record shows the send
  glyph): a key change mid-gesture tears down the hold-to-record pointer
  stream. Both sit in the same 48px slot so the text field does not reflow
  on the first character. Every send button uses `SendIcon`
  (`send_icon.dart`), which carries the plane's optical-centering nudge.
- **`customImageResizer` can't enforce a refusal**: the SDK swallows a
  throwing resizer and sends the original bytes, which is why image
  preparation happens app-side before `sendFileEvent`.
- **`light_compressor` rejects sources under 2 Mbps by default**
  (`isMinBitrateCheckEnabled`), which covers most screen recordings and
  forwarded clips; it is disabled. Its bitrate option is whole megabits.
- **The video cap is on the long edge**: a landscape 1080p clip lands at
  720×404, not 1280×720. Deliberate so far; bump `videoLongEdge` and the
  720-tier bitrate together if that changes.
- **A 4K clip encodes at about 1.3× real time** through the hardware
  decoder and encoder; the bar's 50/50 split makes that read slower than
  the old full-bar compression, but the encode itself is unchanged.

## Extension Guidance

- **Adding a new message/event shape** (new msgtype, new content key):
  1. Add handling to `isDisplayableTimelineEvent` and `summarize` in
     `event_display.dart` — this is the only place classification belongs.
  2. Add a `MessageKind` case if it needs its own rendering — every switch
     site will fail to compile until handled, by design.
  3. Add a row to `event_display_test.dart`'s table (visibility, hidden-mode
     visibility, previewability, kind, text).
  4. Never special-case a new type directly in `RoomPage`'s preview/filter
     logic, the room-list tile, or the notification body — route through
     `event_display.dart` instead, even if it feels like a one-off.
- **Adding a new attachment kind**: follow the two-tier cache
  (`fetchCachedAttachment` for small media, `fetchCachedAttachmentFile` for
  anything large) for fetch/display, and the pending-send pattern
  (synthetic tile keyed by `txid` until the real event lands) for the send
  UX, rather than inventing a new loading state.
- **Anything that needs "the newest real message"** (room list preview,
  read-marker, notification): don't assume `room.lastEvent` is already the
  right answer — it can be an edit, a hidden signaling event, or an
  encrypted envelope. Resolve through `event_display.dart`'s helpers
  (`isPreviewableLastEvent`, `summarize`), not a fresh ad hoc check.

## Dependencies / Integration

- **`matrix` SDK**: `Client`/`Room`/`Timeline`/`Event` are the app's state;
  no repository layer sits between them and the UI.
- **Calls**: call summary/invite/decline are ordinary `m.room.message`
  events with app-specific msgtypes, classified through the same
  `event_display.dart` path as everything else; call UI itself is a
  separate feature (`CallSession`/`CallEngine`, see CLAUDE.md).
  `isMissedCallSummary` is the single rule ("ended"/"declined" describe
  something the recipient took part in, so only a missed call is
  notification-worthy) shared between the live-sync and push notification
  paths.
- **Notifications**: the notification body is `summarize(event).text`, the
  same call the room-list preview makes, so the two never disagree.
- **Security/verification**: in-room verification signaling
  (`verification_signaling.dart`) is filtered out of previews/timeline the
  same way call signaling is, via `event_display.dart`.
- **`light_compressor`**: video re-encoding only (remux, probe and
  thumbnails are this app's own Kotlin); required several native Android
  Gradle patches to build at all (missing `namespace`, mismatched
  Java/Kotlin JVM targets, an outdated `compileSdkVersion` in its own
  module) and pulls from JitPack, not Maven Central — durable build
  requirement, not a one-off fix.
- **`blurhash_dart` + `image`**: blurhash for sent media, computed by this
  app from a 32px sample; the `image` package is never used to decode a
  full-size photo any more.
- **`androidx.exifinterface`**: orientation read in `ImageResizer.kt`
  (the only EXIF field that survives, as pixels).
