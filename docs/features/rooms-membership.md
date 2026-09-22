# Rooms & Membership

## Overview

Covers the room list, room creation/joining, room info & settings, the
4-tier role/permission model, invitations (both sides), and moderation
primitives (block/ignore/report). Zuno targets one self-hosted, non-
federated homeserver — that single fact shapes ID entry, permission
defaults, and what "finding people" can mean.

Room roles & permissions and invitations are called out in the codebase
map as architecturally load-bearing: `room_roles.dart` + `room_permission.dart`
(4-tier model on `m.room.power_levels`), and `room_invite.dart` (deliberately
asymmetric sender/receiver views).

## Architecture

- No repository layer: room-list, room-info, and settings screens call
  `matrix` SDK methods directly on `Client`/`Room` (`room.setName`,
  `room.kick`, `client.createGroupChat`, ...). SDK types are the app state.
- `lib/core/matrix/room_invite.dart` — pure, unit-tested functions reading
  room state to decide invite display/notification behavior. Shared by the
  room list, `RoomPage`'s app bar, and both notification paths (live +
  push).
- **The chat list is split from its page.** `RoomListPage` keeps the
  page-level duties (new-chat flows, onboarding, verification and
  incoming-call listeners, the long-press sheet); `ChatListView` draws.
  Each sync tick a room is read into a value-equal `ChatRowData`
  (`features/rooms/data/`) holding everything the row *displays*, computed
  time label included; `RowMemo` returns the identical `ChatRow` when the
  record is unchanged, which Flutter skips, so a sync rebuilds only the
  rows that changed. The list's delegate has a `findChildIndexCallback`
  keyed on the room ID: without it a chat jumping to the top shifts every
  index and remounts the rows in between, memo or not. `ChatRow` is presentational (its preview is a widget
  slot, filled by `LastMessagePreview`); `InvitationGroup` holds incoming
  invitations above the chats. Rows share one height through a prototype
  (`SliverPrototypeExtentList`).
- `room_exit.dart` — the leave/forget rule plus the shared confirm prompt
  and its copy. `room_title.dart` — `roomTitle()`, the one name every
  surface shows for a room.
- `room_roles.dart` — the 4-tier role model and role-assignment rules
  (`assignableRolesFor`, `canManageMember`, `bannedUserIds`).
- `room_permission.dart` — the permission catalog, each entry mapping to a
  field/`events` override in `m.room.power_levels`, plus
  `defaultGroupPowerLevels(public:)` for new-room creation.
- `abuse_report.dart` — reasons, the reason string and the two send
  calls (`reportMessage`, `reportPerson`). `report_sheet.dart`
  (`lib/features/reports/`) is the one sheet every entry point opens: a
  message's long-press menu, the member sheet, chat info, the invitation.
- `block_person.dart` (`lib/features/blocking/`) — `confirmAndBlockPerson`,
  the one dialog behind every Block entry point (chat info, the member
  sheet, "Block and decline" on an invitation), `blockOnServer`
  (`client.ignoreUser`) and `canBlockPerson`. `blocked_people_page.dart`
  is the list under Settings → Security, with Unblock.
- `call_member_state.dart` — owns the call-specific power-level gate
  (`m.call.member`) and `hasSomeoneToCall`; reused by room permissions and
  by the room list's call-button gating.
- Native Android `MethodChannel` (`android/.../MainActivity.kt`) backs
  "Add to home screen" (pinned shortcuts) — no Flutter plugin exists for
  Android's pinned-shortcut API.
- `public_rooms_sheet.dart` — the directory search sheet behind the room
  list's "+ → Find public rooms". Takes an injectable `PublicRoomsSearch`
  (defaults to `client.queryPublicRooms`), 20 rooms a page, loads the next
  page when the end scrolls into view, drops `m.space` rows client-side,
  and discards responses superseded by a newer search (generation counter).
  Hands back a room ID; the room list joins and opens it.
- `room_access.dart` — public/private as one concept over two server facts
  (join rule + directory listing), plus the admin-only gate and
  `createGroupRoom`, the one call behind the room list's "New room" dialog
  (name + Private/Public, private by default).
  `room_access_label.dart` renders it (globe / crossed globe) in the room
  info header next to "Encrypted" and under the name in the chat header.
- `room_avatar.dart` — upload + state write + optimistic state in one
  step; the SDK's `setAvatar` returns only an event ID, which left every
  page stale until reopened.
- Room info layout: a header (avatar, name, Encrypted • access), a row of
  quick actions, then `CardGroup`s. Quick actions are Call and Video (only
  when `RoomInfoPage.onStartCall` is given, the room allows it and someone
  else is there; `RoomPage` passes a callback that pops the page and
  starts the call), Mute/Unmute, and Invite. Block, Report and the exit
  row (`roomExitLabel`) close the page; exiting pops
  `RoomInfoResult.left`, and `RoomPage` then pops itself. Members are
  requested in `onRouteSettled`; if the request fails, the members already
  in memory show and the count comes from the room summary.
- Room info members: `member_tile.dart` (shared row; badge from
  `memberBadge`) and `members_sheet.dart` (full list, searchable, same
  rows). The page shows five, owner first (`membersOwnerFirst`), then
  "View all members". `RoomInfoPage` listens to `client.onRoomState` so
  settings edits (all applied optimistically) show without reopening.
- Room info media: `lib/core/matrix/room_media_feed.dart` is a per-room,
  cursor-paged feed over the SDK's `Room.searchEvents` (local database
  first, then server history in pages of 100 events, decrypting as it
  goes). One load gathers up to 40 media events across at most 4 requests,
  dedups by event ID, prepends new media from `client.onTimelineEvent`
  and drops redactions. Kind (photo/video/file) comes from
  `event_display.dart`'s `summarize`; voice messages are excluded.
  `roomMediaFeedProvider` (keep-alive family keyed by `Room`) caches feeds
  for the session and invalidates itself on logout. `room_media_section.dart`
  previews six thumbs plus a "More media and files" row;
  `room_media_page.dart` is the tabbed page (photos and videos by month,
  files) that auto-loads while history keeps yielding media, offers "Load
  older" after a dry stretch (`stalled`) and "Try again" after a failure
  (`failed`). Thumbs open `GalleryViewerPage` over the loaded list.

## Data & State

- **Single source of truth**: Matrix room state, read live off the SDK's
  in-memory `Room`/`Client.rooms`, not a local duplicate.
- **Role model**: a 4-tier scheme layered over the raw power-level int —
  read-only (`-1`), member (`0`), moderator (`50`), admin (`100`). `-1` is
  a Zuno-specific extension (not part of the wider Matrix/Element 0/50/100
  convention); verified against SDK source that power levels aren't
  floored at 0. Read-only behavior (can't message, can't edit room
  metadata, can't join calls) isn't separately implemented — it falls out
  for free from existing per-feature power-level checks.
- **Permission catalog** (`room_permission.dart`): each entry maps to a
  field or `events` override on the room's single `m.room.power_levels`
  state event. Every read/write path is checked against the real SDK
  getters it must stay consistent with (`canBan`, `canKick`,
  `canSendEvent`, `canSendDefaultStates`, `canSendNotification`, etc.),
  never hand-rolled separately.
  - `users_default` is *not* a permission — it's the room's default-role
    *value*, exposed as its own "Room defaults" setting
    (`roomDefaultRoleSetting`), not a row in the permission list.
  - Deliberately excluded from the catalog: `m.room.server_acl` (no
    federation — nothing to gate), room upgrade/tombstone (high-
    blast-radius, no SDK convenience method, needs its own design pass),
    "modify widgets" (no widget feature exists to gate).
- **New-room defaults**: `defaultGroupPowerLevels()` builds a
  `power_level_content_override` from Zuno's own fixed role table (name/
  topic/avatar/main-address/settings/history-visibility/permissions/
  encryption at admin; invite/send-messages at member; kick/ban/redact/
  notify at moderator) and passes it to `Client.createGroupChat` — because
  homeserver presets (e.g. Synapse's `private_chat`) default several of
  these to moderator, which would silently disagree with Zuno's own
  permissions UI the moment a room is created. `users_default` is left
  unset since its spec fallback already matches Zuno's own default.
  A public room differs only through `_publicRoomPermissionRoles`
  (start or join calls at moderator). It applies at
  creation only: making an existing room public leaves its permissions
  alone, because an admin may have set them.
- **Invitation state** is nothing but a room's `m.room.member` event(s) —
  no separate invite entity. `RoomSummary` fields
  (`m.invited_member_count`, `m.joined_member_count`, `m.heroes`) are used
  wherever "is someone still deciding" must survive a cold start, since
  full member state does not (see Gotchas).
- Banned users: read from cached `m.room.member` state
  (`bannedUserIds`) — the SDK has no dedicated "list bans" call.

## Communication

- All room/membership actions go straight through `matrix` SDK methods:
  `Room.join()`, `Room.leave()`, `Room.forget()`, `room.kick`/`ban`/`unban`,
  `room.setName`/`setDescription`/`setAvatar`, `setCanonicalAlias`,
  `setHistoryVisibility`, `enableEncryption`, `Client.createGroupChat`,
  `Client.getUrlPreview`, `Client.getUserProfile`,
  `Client.queryPublicRooms` (`POST /publicRooms`, `generic_search_term`),
  `Client.joinRoom`, `Room.setJoinRules`,
  `Client.setRoomVisibilityOnDirectory`.
- **Invite delivery, live**: `client.onNotification` (not
  `onTimelineEvent`) — an invitation is stripped `invite_state` for an
  unjoined room, not a timeline event; the SDK gates re-emission on
  `prevBatch` so a sync backlog doesn't fire all at once.
  `roomInviteNotificationProvider` watches this continuously from
  `RoomListPage.build()`.
- **Invite delivery, push**: `incoming_push_handler.dart` routes through
  `inviteNotificationFor` — the same pure function the live path uses —
  because the default push handler (`messageNotificationFor`) only
  recognizes `m.room.message` and silently drops `m.room.member` (invite)
  pushes.
- Tapping an invite notification opens `RoomInvitePage` via `app.dart`'s
  `_openRoomById`, never the room itself — an unjoined room has no
  timeline or composer.
- Link previews: fetched and OG-parsed server-side via
  `client.getUrlPreview` (`preview_url` endpoint) — the client never
  contacts the linked site directly. Only scans plain text-shaped
  messages, not attachment captions/filenames.
- All ID entry/display is local-part-only, everywhere — see Key Design
  Decisions (server isolation).

## Key Design Decisions

- **The official Zuno chat is identified by who created it, not what it is
  called.** `isOfficialZunoRoom` (`lib/core/matrix/official_room.dart`)
  requires both the server-set `m.server_notice` tag and
  `@notices:zuno.chat` as the room's creator; the badge then shows in the
  chat list and the chat header. A user can tag their own rooms but cannot
  forge a creator, so the badge cannot be copied. The user id carries the
  `zuno.chat` domain literally.
- **Room names cannot contain "Zuno".** `roomNameError`
  (`lib/core/matrix/room_name_check.dart`) lowercases the name and reads
  `0` as `o`, so `Zun0` is refused too. It gates the new-group dialog and
  the rename dialog. This is client-side only: the API accepts anything, so
  a server-side check is the one that enforces it.

- **Public means listed *and* open.** "Public" sets the join rule to
  `public` and publishes the room to the server directory; "private" sets
  `invite` and unlists. One without the other is either invisible or
  unjoinable. The write order is chosen for its failure mode: public lists
  first, then opens (a refused listing changes nothing); private closes
  first, then unlists (stopping joins wins). Admin-only by app policy, same
  as permission editing; a confirmation lists the consequences per
  direction. The chat header marks only public group rooms (a globe) — the
  same "mark the exception" rule as the encryption icon.
- **A new public room is one `createRoom` call** (`public_chat` preset +
  `visibility: public`, still encrypted), not create-then-`setRoomAccess`:
  a server that refuses listing then creates nothing, instead of leaving a
  private room behind an error. The dialog states what Public means under
  the choice, so creation has no separate confirmation.
- **"Join room" by ID stays in the + menu but disabled** — parked behind
  directory search, not removed, so the local-ID dialog can come back.
- **Owner is the create-event sender** (`isRoomOwner`, plus
  `additional_creators` on v12 rooms): sorted first and badged "Owner" for
  everyone, but still an admin underneath. Role badges (Admin/Moderator/
  Member) show only to admins and moderators; "Invited" and "Owner" show to
  all. The Advanced section (room ID/alias) shows to owners and admins, in
  rooms and chats alike — a chat gives both people admin level.
  On room versions below 12 the creator can be demoted, so ownership is a
  label, never a permission gate.
- **Direct chats hide Members, Advanced and keep only Security**; group
  rooms hide the Security section entirely (encryption is universal, and
  the per-person trust rows belong to the 1:1 relationship).
- **Room access changes ask first** with the consequences of that
  direction; editors cap name (50), topic (250) and address (50).
  Clearing the address deletes the old alias from the directory
  (tolerating not-found) and writes an empty canonical-alias state;
  sending `#:server` is exactly what an unguarded empty value did.
- **Server isolation**: since Zuno targets one self-hosted, non-federated
  homeserver, the server part of a Matrix ID is never shown or asked for.
  User lookups (DM start, room invite) take only a local username (`@` is
  a static prefix); joining a room takes just the alias/ID local part with
  sigil picked via toggle; any read-only ID display shows sigil + local
  part only (`@user`, never `@user:homeserver`), including a mention
  rendered in a message. The part the dialogs append is the account's own
  server name (`ownServerName`, `server_name.dart`) — never
  `client.homeserver.host`, which is the delegated API host and made every
  local invite look federated. No exceptions remain.
- **Sender/receiver invite views are deliberately asymmetric.**
  - *Sender side*: no profile is shown for an unaccepted invitee — the
    server hands over their `m.room.member` state before they've agreed to
    anything, "a promise the room hasn't earned." The room is titled with
    the typed Matrix ID, no avatar, until accepted. A room with its own
    name/avatar is exempt (that's about the room, not the person).
  - *Receiver side*: the inviter's name and avatar are shown in full,
    because "who is this?" is the entire question being asked.
  - This reasoning quietly assumed the inviter is probably known to the
    recipient. A planned change **amends, not reverses**, the receiver
    rule for first-contact invites from strangers (see Known Gaps) —
    full disclosure is preserved once the user has actively asked
    (opened `RoomInvitePage`), not before.
- **Permission-gated feature surfaces check "can do X", never "will the
  server accept this"** — e.g. `canSendDefaultMessages` gates the
  composer (swapped for a notice rather than an ambient disabled state)
  specifically because it already accounts for encrypted/tombstoned rooms
  correctly, avoiding a class of `M_FORBIDDEN` round trips discovered only
  after the fact.
- **Room-info permission editing is admin-only by app policy**, stricter
  than the room's own configured "change permissions" level: admins edit,
  moderators see read-only, members/read-only members don't see the entry.
  Because every value this UI writes is ≤100 and editing requires level
  100, Matrix's "sender level must be ≥ both old and new value" rule is
  satisfied by construction with no extra runtime validation.
- **Per-member role/kick/ban actions** layer an app-level business rule
  (only admins create admins; moderators can only move someone down to
  member/read-only) on top of the server-enforced rule (can't act on
  someone whose level is already ≥ yours). The app rule is strictly
  narrower, so the UI never offers an action the homeserver would reject.
  Self-editing is always excluded.
- **A signal that never varies carries no information**: the room list's
  encryption lock icon was removed as a per-room badge (every room is
  encrypted by default, so it was constant noise) and inverted to only
  mark the rare *unencrypted* room (reachable via manual join-by-ID/alias)
  — silence is the safe/default state, a mark is reserved for the
  consequential exception. This freed-up attention budget is shared with
  `security-verification.md`'s attention system (`security_emphasis.dart`)
  — the room-list row is one of the surfaces it governs.
- **Three unrelated conditions share one dimming treatment**
  (`ChatRowData.dimmed`): muted means "you asked not to hear from it,"
  pending means "there is no conversation here yet" — nothing to read,
  nobody to call (see `hasSomeoneToCall` below) — and partner-left means
  "this one is over." All three reduce to "this row isn't one of your live
  chats," which a muted name color says at a glance while a title-row glyph
  and the subtitle carry the specifics: a clock and "Waiting for … to
  accept", a crossed-out person and "Left the chat". Dimming is by color,
  never `Opacity` (an off-screen pass per row), so combinations cannot
  compound into something unreadable.
- **The one-person/group indicator is a badge on the avatar, not a
  separate glyph in the title row** (`room_kind_avatar.dart`) — it used
  to sit ahead of the room name, competing for the tile's one line of
  horizontal space and pushing the name right whenever a mute bell or
  pending clock was also present. On the avatar it costs no width. Filled
  rather than outlined (it overlays a photo of arbitrary colour) on a
  `surface`-coloured disc so it reads as punched out of the avatar. Not
  styled as a security indicator, and unlike the lock badge it replaced,
  this one genuinely varies row to row.
- **Calls require a real callable party, not just permission.** Call
  buttons are gated on `canPublishCallMemberState` *and*
  `hasSomeoneToCall` (at least one joined member besides self) — a
  permission check alone let an unaccepted invite or an emptied-out group
  offer a working call button that could never connect a second party.
- **One kind-aware exit, not "leave" plus "delete".** The two were
  indistinguishable to a user: `client.rooms` excludes left rooms, so both
  made the row vanish and only the server-side archive differed.
  `exitRoom()` (`room_exit.dart`) always leaves and forgets **only** a
  direct chat, which has no history to come back to; a group is left but
  kept, since it persists without you and may be rejoinable. Declining an
  invite is the same question, so `declineInvite` delegates to it rather
  than restating the rule. The label follows the kind — "Delete chat" on a
  DM, "Leave room" otherwise — and both the room list sheet and the
  RoomPage menu confirm first.
- **An abandoned DM is read-only, not broken.** Once the other person
  leaves (`Room.isAbandonedDMRoom`) the SDK names the room "Empty chat
  (was Bob)", which is both techy and wrong — the history is still there.
  `roomTitle()` (`room_title.dart`) returns their name instead and is the
  single title source for every surface: list, chat, notifications, push,
  calls, room info, share picker. `canPostInRoom()` then drops the
  composer, mention suggestions, swipe-to-reply and the reply/react/edit
  actions. Redaction deliberately stays — removing your own message is
  cleanup, not communication. Call buttons needed no new gate:
  `hasSomeoneToCall` already requires `joined > 1`, and an abandoned DM
  has exactly one.
- **Moderation tooling lives outside the app entirely** (planned, not
  built) — this reaffirms, rather than contradicts, the standing "no
  admin-facing surface" rule for a personal client turned public service.
  Reports/suspension/room-shutdown are meant to be handled through a
  separate operator surface (web console, CLI, Synapse Admin) the client
  knows nothing about.
- **Reports go to the operator, not to room admins.** Room admins own what
  happens inside a room (remove, ban, delete); a report is the only channel
  to the operator, for what admins cannot cover — chats and invitations
  (no admin), an abusive admin, illegal content, account-level action. The
  sheet says so in rooms. Anyone can report anyone but themselves.
- **A report carries IDs and a reason, never content.** Everything is
  end-to-end encrypted, so the server gets the event or user ID plus a
  reason string; the copy says Zuno cannot read the message and asks for a
  description. Reason format, built for filtering:
  `category[: note] [(room <id>)]` with categories `spam`, `harassment`,
  `illegal`, `other` (`other` requires a note).
- **An invitation is reported by its sender**, with the room ID in the
  reason: invite state has no event ID to report, and the sender is the
  signal invite-abuse limits need. "Report and decline" declines only after
  the report is accepted; a refused report leaves the invitation alone.
- **Blocking is the SDK's ignore, with its defaults.** `ignoreUser` leaves
  the chat with that person, declines their pending invitations, stores
  them in `m.ignored_user_list` and clears the local cache, so the server
  re-sends every room without their messages. Leaving is deliberate: a
  kept chat would show one side only and still let the blocker send. The
  cost is that unblocking never brings the chat back, which the dialog
  says, and only when a chat exists.
- **Anyone can block anyone, whatever their role** — it is the one
  moderation tool that works in chats and on invitations, which have no
  admin. Google Play requires it for direct messages.
- **The official `@notices:zuno.chat` account cannot be blocked**
  (`canBlockPerson`): server notices carry the shutdown notice the terms
  promise.

## Gotchas & Constraints

- **Mute waits for the push-rules sync.** `room.setPushRuleState` returns
  early when the new state equals `room.pushRuleState`, and that only
  changes when the next sync delivers `m.push_rules`; a Mute followed at
  once by Unmute would otherwise be a silent no-op. `_setMuted` locks while
  in flight, shows the new state at once, and keeps that override until
  the push-rules sync arrives (or 10 s pass). A refused request flips back
  and says so.
- **The media feed's first load always hits the server once** —
  `searchEvents` does the full local-database scan and the first server
  page in one call, even when the database already held enough media.
  Live prepend skips events that fail to decrypt on arrival; they show
  only after a fresh feed. `CustomScrollView` adds no system inset on its
  own — the media page's load footer is wrapped in `SliverSafeArea` so the
  last grid row clears the navigation bar.
- **Synapse ≥ 1.126 refuses directory publishing by default**
  (`room_list_publication_rules`). Without an allow rule "Find public
  rooms" lists nothing and "Public" fails; the app maps the server's
  "Not allowed to publish room" to "This server doesn't allow listing
  rooms" and leaves the room private.
- **The access indicator reads the join rule, not directory visibility** —
  visibility needs an HTTP call per room. A room listed by other means but
  still invite-only reads as private.
- **A record that can go stale is a stale row.** `ChatRowData` must hold
  every value the row or its preview shows, plus the last event's ID and
  status (not rendered, but they keep the memoized preview on the current
  `Event` instance; see `chats-messaging.md` on `lastEvent` identity).
  Adding something to the row means adding it to the record.
- **Every text line in a chat row is strut-locked** (`core/ui/line_strut.dart`).
  The list is fixed-extent; measured with real fonts, Thai and Devanagari
  grew a row 2 to 6 px at larger font-size settings until it was.
- **A tinted tappable surface is a `Material`, not a decorated
  `Container`**: ink paints under a Material's child, so an opaque
  container hides the ripple (`InvitationGroup`).
- **`ChatListView` and `ChatRow` test without the page**, from fake rooms
  (`buildTestRoom`, `room.setState`, `room.lastEvent = …`).
- **`RoomListPage` and `RoomPage` do render in widget tests** with
  `TimelineCapableFakeDatabaseApi`, `room.partial = false`, a `MockClient`
  drained via `tester.runAsync`, and an `UncontrolledProviderScope` whose
  container outlives the tree (`RoomPage.dispose` touches a provider in a
  microtask). `RoomPage` never settles — use bounded pumps.
- **Member state is not loaded on cold start**, and an invitation *is*
  nothing but member state. `getRoomList` (cold-start room rebuild) reads
  the preload box only, never the separate `_roomMembersBox` that
  `m.room.member` events are filed into. Symptom class: inviter shown as
  "Someone", a DM invite accepted into a group room instead, a sender's
  own pending indicator vanishing after restart. Mitigations:
  `loadInviteMembers` reads the member box directly and restores it before
  any accept/decline; anything needing "is someone still deciding" prefers
  `RoomSummary` fields (survive cold start) over live member state.
- **A member event whose sender is its own subject is a fallback
  substitute, not a real invitation** — `unsafeGetUserFromMemoryOrFallback`
  synthesizes one from the global profile when a member event can't be
  found (invite rooms refuse `/state` pre-join), overwriting real invite
  data. Detected by checking sender == subject (nobody invites themselves)
  and treated as "not loaded."
- **Cross-user verification cannot reach someone who hasn't accepted an
  invite** — `startVerification` sends a room message, and an invited user
  has no timeline yet, only stripped `invite_state`. The UI shows a
  passive "You can confirm them once they join" row instead of opening a
  verification flow that would hang. Verifying someone from a *group* room
  you've never DM'd silently creates a new DM and waits on their
  acceptance — same underlying limit, left as-is (slow, not wrong).
- **A room can never be truly server-agnostic on identity checks**:
  confirming a contact requires your own device to be verified first (SDK
  can't sign another identity from an unverified device) — this chains
  into a forced recovery setup rather than silently hiding the option.
- **E2EE permanently rules out content-based spam/abuse filtering** at
  the server. Every server-side signal available to combat invite spam or
  abuse is metadata only (account age, IP, invite fan-out, accept ratio,
  burst timing) — "filter spam later" is not an available plan.
- **Profile lookups are an account-enumeration oracle.** A pre-invite
  `client.getUserProfile` existence check (proposed, not yet built) is
  in tension with the login form's single-error-message anti-enumeration
  design, and needs its own server-side rate limit; some Synapse configs
  (`require_auth_for_profile_requests`,
  `limit_profile_requests_to_users_who_share_rooms`) also break the check
  outright and need a fallback.
- **The "first-contact" test has a cold-start blind spot.** The cheap
  client-side test for "have I ever shared a room with this inviter" runs
  over `client.rooms`, but member state is exactly what's missing on a
  cold start — and push-triggered invite handling *is* a cold start. Not
  yet resolved; recommendation on record is to fail quiet (treat as
  known/trusted) rather than loud when the test can't answer, since a
  false negative costs one non-critical notification while a false
  positive is the entire spam problem re-opened.

## Known Gaps (planned, not yet built)

These are open problems, not implemented and not silently resolved
elsewhere:

- **Invite-spam notification hardening.** First-contact invite
  notifications and the inline room-list tile currently surface fully
  attacker-controlled strings (inviter display name, room name) straight
  to a lock screen with no acceptance required. Planned fix: fixed,
  neutral copy ("New chat request") for senders with no shared history,
  plus a quiet, un-notified "Requests" section in the room list —
  contingent on resolving the first-contact test's cold-start gap above.
  Note the in-flight MSC4155 (client-controlled invite filtering) should
  be checked before building a bespoke account-data schema for this.
- **Server-side invite-abuse limits** (spam-checker module): capping
  outstanding unaccepted invites per sender, decline/ignore ratio as
  reputation, and tiered limits by account age/reciprocated contact.
  None exist yet; entirely server-side (`user_may_invite` module), no
  client change required.
- **Existence check before DM creation.** `_startDirectMessage` currently
  creates the room before inviting, so a typo'd username leaves a
  permanent orphan room waiting for someone who doesn't exist. No
  pre-check exists yet (see enumeration-oracle gotcha above for why it's
  non-trivial).
- **Blocked people show as usernames only.** The server refuses profile
  lookups for people you share no room with
  (`limit_profile_requests_to_users_who_share_rooms`), which is the usual
  case after a block.
- **Whether Synapse suppresses a blocked person's invitations and push is
  unconfirmed** — expected, not yet checked with two accounts.
- **Moderation stays out of the app** (see Key Design Decisions). The admin
  reads reports on the operator side; reports have no retention period
  yet. They are also the input signal the reputation-based invite limits
  above would depend on.
- **No way for two strangers to find each other as people.** Rooms are
  discoverable through the public directory now; people still only by
  exact username. Spaces stay permanently excluded
  (see `design-spec-excluded.md`). Two candidates on record: user-
  directory search (another enumeration surface, needs rate limiting) and
  invite links (opens a DM with the link's generator, no directory, no
  enumeration) — invite links are the recommended first answer as cheaper
  and safer.

## Extension Guidance

- New permission-gated feature surfaces: add a catalog entry to
  `room_permission.dart` mapped to the real SDK getter it must agree
  with — never hand-roll a second power-level check. Follow the existing
  per-field `canChangeStateEvent` pattern rather than one blanket
  "can edit room" check.
- New member-facing actions (kick/ban-shaped): reuse `canManageMember`
  (`room_roles.dart`) for the self/peer/superior exclusion rather than
  reimplementing the "sender level must exceed target's current level"
  rule.
- Any new invite-adjacent UI (block, report, requests section) belongs
  alongside `room_invite.dart`'s existing pure-function shape — decide the
  "shared history" / first-contact test once, in one place, and reuse it
  rather than letting notification and room-list code drift into separate
  checks.
- Anything that needs to survive a cold start before full member state is
  loaded should prefer `RoomSummary` fields, following the precedent set
  by invite-pending detection and `hasSomeoneToCall`.
- Room upgrade/tombstone and `m.room.server_acl` are deliberately absent
  from the permission catalog — don't add UI for either without a
  dedicated design pass (upgrade is one-way and high-blast-radius; ACLs
  govern federation, which doesn't exist here).
- A new place to block from: call `confirmAndBlockPerson`, hide it behind
  `canBlockPerson`, and leave the screen afterwards — the cache clear
  makes every open `Room` stale, so chat info pops to the chat list.
- Widget tests inject `blockPerson`/`unblock`: the fake database cannot
  clear a cache. `block_on_server_test.dart` runs the real call against a
  fake server instead.
- A new thing to report: add an entry point that opens `showReportSheet`
  with its own title and explanation, and send through `abuse_report.dart`
  so the reason format stays one format. The server also accepts room
  reports (`client.reportRoom`); nothing uses it yet.
- Moderation/report features must not grow an in-app admin screen — route
  any such need to the separate operator-facing surface described above
  (Known Gaps).

## Dependencies / Integration

- `matrix` Dart SDK: source of truth for all room/membership/power-level
  state; several decisions here were verified directly against SDK source
  (power levels not floored at 0; `canSendDefaultMessages` semantics)
  rather than assumed.
- Notifications (`NotificationDeliveryProvider`, live `onNotification`
  path, and `incoming_push_handler.dart`): invitations are one of the
  event types both paths must independently recognize.
- Security & verification (`lib/core/security/`): cross-user confirmation
  is blocked by invite-pending state and by the confirming device's own
  unverified/no-recovery status; the confirm flow chains into
  `SecureBackupPage` when needed.
- Calls (`CallSession`/`call_member_state.dart`): call permission and
  "someone to call" gating is shared between Room roles & permissions and
  the room list's call-button logic.
- Event display (`event_display.dart`): room-list previews (e.g. "Waiting
  for @bob to accept") take precedence over normal last-message summaries
  while an invite is pending.
