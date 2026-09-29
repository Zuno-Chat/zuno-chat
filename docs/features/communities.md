# Communities

## Overview

Matrix spaces, called **communities** in the app ("space" and "group" are
not Zuno words). A community is a family, club or team with several rooms.
Home has two tabs: Chats and Communities.

## Architecture

- `core/matrix/communities.dart` — `arrangeHome` splits `client.rooms` once
  per sync into chat invitations, chats, community invitations, communities
  (newest room first) and each community's joined rooms. One result feeds
  both tabs and the bar's unread dots. Also create, leave and the
  `/hierarchy` read.
- `rooms/presentation/home_bottom_bar.dart` — a pill like the chat
  composer, with the amber round + beside it (no floating button). Only the
  visible tab is built; a `PageStorageKey` keeps each list's scroll. Back
  on Communities returns to Chats; the app always opens on Chats.
- `ChatListView.chats` / `.communities` — one list, two feeds; a community
  row is an ordinary fixed-height `ChatRow` (`ChatRowData.community`,
  `previewSource` for "Room · preview").
- `communities/presentation/community_page.dart` — header, Invite and New
  room, "Your rooms", "More rooms" (Join / Ask / Requested), members with
  roles, and the ⋮ menu (settings, Roles & permissions, Leave).
- Ask to join: `core/matrix/join_requests.dart` (both sides),
  `join_requests_view.dart` (chat card, Review sheet, room info card),
  `core/notifications/join_request_notification_provider.dart`.
- Rules: `communityPermissionGroups` shown by the shared
  `RoomPermissionsPage`.

## Key Decisions

- **Chats never shows a community or a room inside a joined community.** A
  direct chat listed in a community stays in Chats; so does a room whose
  community you have not joined.
- **New communities**: settings admin-only, adding rooms moderator+,
  inviting any member, messages nobody (`communityPowerLevels`).
- **A community room is Community, Ask to join or Private — never Public.**
  Community is `restricted` to the community, Ask to join is `knock`. App
  rule only; another client can still publish one.
- **Leaving a community leaves the rooms no other joined community holds.**
- **Rooms do not inherit community roles.** Matrix has no inheritance.
- **Only moderators and admins answer requests**: declining is a kick,
  which Zuno gives moderators and up.
- **An approved request is joined automatically.** Requested room IDs live
  per account in SharedPreferences (`communities.asked.<userId>`); a failed
  automatic join forgets the request so the approval shows as a normal
  invitation. Approvers are notified only while Zuno runs (no push rule).

## Communication

- `/hierarchy` (depth 1, 50 rooms) runs on page open and pull, and only when
  a listed child is not joined.
- Knock with the community's `via`; withdraw is a leave; let in is an
  invite; decline is a kick.
- Find public communities asks the directory with `room_types: [m.space]`;
  Find public rooms drops spaces client-side.

## Gotchas

- A space never opens a timeline, so `CommunityPage` calls `postLoad()`:
  topic, join rule and power levels are not loaded at cold start
  (`m.room.create`, `m.space.child` and `m.space.parent` are).
- The SDK never creates a `Room` for your own knock; the requested state is
  Zuno's to keep.
- `requestParticipants` caches members only in encrypted rooms unless asked
  to; requests are looked up only where the join rule allows knocking.
- The community page rebuilds only for syncs touching it or its rooms, and
  closes itself when you are removed.
- Removing someone from a community leaves them in its rooms, and the
  dialog says so.
