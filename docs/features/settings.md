# Settings

## Overview

The Settings area is the app's one catch-all for account and app
preferences. It replaced the room list app bar's overflow menu entirely —
that menu used to hold "Edit profile," "Sessions," and "Sign out"; all
three now live in or under Settings.

| Category | Holds |
|---|---|
| Account | Profile picture, display name, username, change password |
| Notifications | Enable, full-screen call alerts, notify-for, sounds & vibration, and a **Delivery** row opening its own page |
| Chats & calls | Theme, typing indicator, prevent accidental calls |
| Data & storage | Reduce media size, use less data for calls, clear cache, clear media cache |
| Security | Status card, recovery, devices, blocked people, incognito keyboard, prevent screenshots, Advanced (disabled placeholder) |
| About | Versions, donate, privacy policy, terms, and Diagnostics: send crash reports, show hidden messages |

Send feedback, Sign out and Delete account sit on the root list itself.

Security & Privacy sub-settings (cryptography, active sessions, secure
backup, key management, app protection) are a sibling feature — see
`docs/features/security-verification.md`. Notification delivery transports
(background sync, UnifiedPush, FCM) and the push pipeline are covered in
`docs/features/notifications.md`. This doc covers the Settings shell itself
and the categories that aren't deep enough to warrant their own doc:
Account, Chats & calls, Data & storage, About, and log-out placement.

## Architecture

- `lib/features/settings/presentation/settings_page.dart` — the entry
  screen, reached from a plain `IconButton` in the room list app bar (the
  old overflow menu is gone). A profile card on top opens Account, then
  grouped cards of categories, then Sign out and Delete account.
- Every settings screen is a `CardListView` of `CardGroup`s
  (`lib/core/ui/`, `app-foundation.md`). `expectEveryRowOnACard`
  (`test/helpers/card_layout.dart`) fails a row left outside a card.
- The profile card costs no request: `own_profile.dart` reads the name and
  picture from own member state already in memory, falls back to a
  database-only lookup on a cold start, and redraws on own member state
  from `client.onRoomState` (a rename in Account shows on return).
- Each category is its own screen under
  `lib/features/settings/presentation/`: `account_settings_page.dart`,
  `notifications_settings_page.dart` (+ `notification_delivery_page.dart`),
  `chats_calls_settings_page.dart`, `data_storage_settings_page.dart`,
  `security_privacy_settings_page.dart`, `about_page.dart`.
- `settings_widgets.dart` — shared row widgets, including
  `ComingSoonTile`/`ComingSoonSwitchTile`: disabled placeholder rows used
  for features not yet built, so the eventual location is visible without
  being interactive.
- `lib/core/navigation/zuno_links.dart` — the website addresses (donate,
  privacy policy, terms) and `openLink`, which opens one in the browser or
  names the address in a snackbar. Google Play requires the privacy policy
  to be reachable inside the app.
- `lib/core/settings/app_preferences_provider.dart` — Riverpod providers
  backing app-wide preferences (theme mode, typing indicator, delivery
  mode enum, etc.), persisted via `shared_preferences`.
- No repository/service layer, consistent with the rest of the app:
  settings screens call `Client` methods directly (`client.setAvatar()`,
  `client.changePassword`, `client.clearCache()`) rather than going through
  an abstraction.

## Data & State

- **Local device prefs** (`shared_preferences`, via
  `app_preferences_provider.dart`): theme mode (System/Light/Dark),
  "Send 'Typing…' indicator" toggle, notification delivery mode enum,
  incognito keyboard toggle. These are per-device, not synced across a
  user's sessions.
- **On by default**: prevent accidental calls, reduce media size, use less
  data for calls, incognito keyboard, prevent screenshots. The default
  applies only while nothing is stored, so a toggle someone already set
  keeps its value across an update. `readPreventScreenshots` is the one
  default for both the provider and the cold-start `FLAG_SECURE` call in
  `main.dart` — change it there, never in one place only.
- **Account data / server state**: display name and avatar go through the
  Matrix SDK (`client.setAvatar()`, profile setters) and are therefore
  account-wide, not per-device.
- **Enum-as-persisted-setting pattern**: `NotificationDeliveryMode` /
  `notificationDeliveryModeProvider` is the model other enum-shaped
  settings should follow — an unrecognized stored value falls back to the
  default rather than crashing; no special-casing needed once every enum
  value has a real implementation behind it.
- Profile visibility (planned, stage 3, not built): a three-tier privacy
  setting for display name/avatar (Public / people-I-share-a-room-with /
  direct-chats-only) would live in Settings → Account, directly under the
  name/avatar fields it governs, with a pointer from Security & Privacy.
  It requires a **server-side** component (Synapse's
  `include_profile_data_on_invite` / `require_auth_for_profile_requests`
  settings plus a module reading each user's choice from account data,
  e.g. `im.zuno.profile_visibility`) — this cannot be a client-only
  preference, since Synapse's controls are server-wide, not per-user.
  Open questions on record: the enforceable/not-enforceable breakdown,
  default tier, and interaction with user-directory discovery and the
  profile-existence check.

## Communication

- `client.setAvatar()` — uploads avatar bytes with no resizing of its own;
  the app shrinks client-side first (512px max, via the same
  `MatrixImageFile.shrink` helper the SDK uses internally for message
  images) before calling it, since a full-resolution photo would otherwise
  be uploaded and re-fetched at full size by every client for an image
  that's only ever shown small.
- `client.changePassword` — password change, called from inside
  `ChangePasswordDialog` so the dialog stays open on a refusal and offers
  the new password to the password manager only once the server took it
  (`authentication.md`). The new password passes the sign-up gate.
- `client.clearCache()` — drops local messages/room state, forces a fresh
  sync on next use.
- Clear media cache — drops the attachment/thumbnail cache (both tiers)
  and the map tile cache (no server call).
- `client.logout` — see "Sign out placement" below for why it's never
  called directly.

## Key Design Decisions

- **Categories follow what people look for, not where the code lives.**
  Everything that costs bytes (media size, call data, caches) is Data &
  storage; theme sits under Chats & calls; diagnostics sit with the
  version rows in About. A page with one or two rows gets merged rather
  than kept as its own category.
- **Delivery is a sub-page of Notifications.** The method picker and its
  per-transport rows (distributor, status, battery, background data) are
  set once and troubleshooting-shaped, so they stay off the everyday
  page. The delivery banner's "Open settings" opens
  `NotificationDeliveryPage` directly.
- **Link previews has no row while `linkPreviewsFeatureAvailable` is
  false.** The provider stays: `room_page.dart` reads it.
- **Security > Advanced is outside the brand voice, on purpose.**
  `AdvancedSecurityPage`, `KeyBackupManagementPage` and the security key /
  security phrase screens of `SecureBackupPage` keep protocol vocabulary
  (session, cross-signing, security key, secret storage): their readers are
  matching terms against other clients. Every other screen follows
  `docs/brand-voice.md`. Do not rewrite these to match.
- **Profile editing is inlined into Account, not a separate page.** The
  old standalone Edit Profile page was merged in and removed — one fewer
  navigation hop for the most commonly touched settings.
- **Avatar shrinking happens client-side before upload**, matching the
  message-image path, rather than trusting the server or every viewing
  client to downscale.
- **Sign out lives in Settings, off the room-list overflow menu.**
  Reasoning: the overflow menu held exactly two items (Settings, Sign out)
  adjacent to each other at the spot people hit by muscle memory — putting
  the single most destructive action in the app one tap from every screen
  next to the most routine one. Signing out isn't frequent, so nothing was
  gained by making it fast. Once Sign out moved, the remaining single item
  had nothing left to disambiguate, so the menu itself was replaced by a
  plain settings icon button.
- **The logout confirmation is asymmetric based on recovery status.**
  `_confirmLogOut` branches on `AccountSecurityStatus.noRecovery`: an
  account with no recovery code loses every local-only room key on logout
  permanently (the local database is cleared) — messages become
  unreadable by anyone, including the original sender. That branch shows a
  warning and offers a one-tap "Set up recovery" button alongside "Sign out
  anyway," rather than a plain cancel-or-proceed dialog that leaves the
  user to solve it themselves. The settled branch (recovery already set
  up) stays an ordinary two-button confirmation.
- **`client.logout` is never called directly** — `_logOut` always tears
  down push delivery first, while the access token is still valid,
  otherwise the homeserver keeps pushing to an endpoint nobody is
  listening to (`stopAllNotificationDelivery`). This is the only path most
  logouts take; preserve this ordering in any new logout entry point.
- **The logout confirmation reads client/security state inside the tap
  handler, not via `watch` in `build`.** This is why its widget test needs
  no provider overrides — a Cancel that ever reached real logout would
  throw rather than silently signing a test client out. Keep this pattern
  for any settings row with a destructive, confirmed action.
- **Cache management is split into two distinct actions** (clear cache vs.
  clear media cache) because they have different costs: one forces a full
  resync, the other just drops an in-memory cache with no network cost.
  Don't collapse them into one button.
- **Donation is one static About row that opens `zuno.chat/#donate` in
  the browser.** Never a prompt, badge or popup (`docs/brand-voice.md`),
  and no in-app payment. The URI must match the site's `#donate` anchor.
  `AboutPage.openUrl` is injectable so tests assert the URI and the
  not-opened snackbar without a platform channel.
- **Delete account's type-to-confirm step shows and matches the local
  username only** — `client.userID` with the `@` and `:server` suffix
  stripped — not the full Matrix ID. The homeserver is implementation
  detail the person never typed in and has no reason to reason about here.

## Gotchas & Constraints

- **Security > Advanced is a disabled `ComingSoonTile`**, so
  `AdvancedSecurityPage` and everything on it is unreachable from the UI
  until the row is wired back to it.
- **`TemporarySessionTokenTile` (Security > Advanced) is temporary — remove
  it before a public release.** It signs in a second device with
  `refresh_token: false` through a bare `MatrixApi` (the app's own `Client`
  is untouched) and shows that access token. The app itself signs in with
  refresh tokens, so its own token expires and is no use for scripts.
  Whether the new token is truly long-lived depends on the server having no
  `session_lifetime`.
- **About's library versions are constants** (`_matrixSdkVersion`,
  `_vodozemacVersion` in `about_page.dart`). `about_page_test.dart` reads
  `pubspec.lock` and fails when they drift, so a dependency upgrade ends
  with updating them.
- `Client.setAvatar()` does no resizing on its own — any new avatar-upload
  path must shrink client-side itself or repeat the full-size-upload
  problem.
- Settings rows for unbuilt features must use the shared
  `ComingSoonTile`/`ComingSoonSwitchTile` widgets, not ad hoc disabled
  widgets, so placeholder rows stay visually consistent and easy to find
  when it's time to wire them up.
- Notification delivery mode is picked via a bottom sheet
  (`_chooseDeliveryMode`), not a `RadioListTile` per mode — the earlier
  radio-list design rendered every mode's own settings section (battery/
  data toggles, distributor status, etc.) inline for every row regardless
  of selection, mostly dead space for unselected modes. A settings section
  with per-option sub-settings should follow the bottom-sheet-picker
  pattern, not the radio-list one, once more than one option has real
  settings underneath it.
- App lock (PIN/biometric) was a disabled placeholder row here but has
  been **cut from the plan entirely** — see `design-spec-excluded.md`. Do
  not resurrect it without checking why it was excluded.

## Extension Guidance

- A new device-local preference (a toggle, an enum, a picker) belongs in
  `app_preferences_provider.dart`, persisted via `shared_preferences`,
  following the enum-as-persisted-setting pattern for anything with more
  than two states.
- A new account-wide setting (anything that should follow the user across
  devices/sessions) should not go through `shared_preferences` — use
  Matrix account data instead (see the planned profile-visibility setting
  for the intended shape: `im.zuno.*` account data key, read/written
  directly via the SDK, no repository layer).
- A new settings category gets its own page under
  `lib/features/settings/presentation/`, listed from `settings_page.dart`.
  Build it as a `CardListView` of `CardGroup`s: a titled card per section,
  single-row sections merged into one untitled card. Reuse
  `settings_widgets.dart` row types before inventing new ones.
- A setting whose implementation isn't ready yet should ship as a
  `ComingSoonTile`/`ComingSoonSwitchTile` in its intended final location,
  not omitted — this project's convention is to make future scope visible
  in the UI.
- Any destructive action (logout-shaped) should read required state inside
  the tap handler rather than via `watch`, both to avoid an unnecessary
  rebuild dependency and to keep the widget test simple (no provider
  overrides needed).
- Profile visibility, when built, is the next Account-page addition —
  place it directly under display name/avatar, and remember the
  server-side module is a prerequisite, not optional client-side scoping.

## Dependencies / Integration

- **Security & Privacy**: reached from Settings as its own section/page;
  full depth (cryptography, sessions, secure backup, key management, app
  protection, incognito keyboard, prevent screenshots) documented in
  `docs/features/security-verification.md`. Settings → Account will link
  to profile visibility once built, and Security & Privacy will point back
  to it.
- **Notifications**: the delivery-mode picker and its transports
  (background sync, UnifiedPush, FCM) are configured from Settings →
  Notifications → Delivery but documented in
  `docs/features/notifications.md`.
- **`matrix` Dart SDK**: `Client` is the single app-wide instance
  (`createMatrixClient()`); Settings screens call its methods directly —
  no service/repository layer, matching the rest of the app.
- **Localization**: not implemented (stage 3, planned) — every Settings
  string, like the rest of the app, is a hardcoded English literal. A
  future localization pass touches every settings screen.
