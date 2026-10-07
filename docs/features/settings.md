# Settings

Settings is the app's one place for account and app preferences. A plain
settings icon in the room list app bar opens it; there is no overflow menu.
This doc owns the shell, its categories and the settings no other feature
owns. A feature's own settings are documented with that feature.

| Category | Holds | Behavior documented in |
|---|---|---|
| Account (the profile card) | Picture, display name, username, change password | here; password in `authentication.md` |
| Notifications | Enable, notify-for, sounds, content (iOS), Delivery, Diagnostics hub | `notifications.md` |
| Chats & calls | Theme, typing indicator, prevent accidental calls | here; accidental calls in `calls.md` |
| Data & storage | Reduce media size, less data for calls, clear cache, clear media cache | here; `chats-messaging.md`, `calls.md` |
| Security | Status, recovery, devices, blocked people, on-device protections, Advanced | `security-verification.md`; blocked people in `rooms-membership.md`; on-device protections here |
| About | Versions, donate, privacy policy, terms, source, licenses, crash reports, hidden messages | here; `crash-reporting.md`, `chats-messaging.md` |

The root opens with the profile card, which leads to Account. Below the
categories sit Send feedback (`crash-reporting.md`), then Sign out and
Delete account (`authentication.md`).

## Architecture

- **Pages**: `lib/features/settings/presentation/`, one per category, each
  pushed from `settings_page.dart`. Every page is a `CardListView` of
  `CardGroup`s (`app-foundation.md`): a titled card per section, with
  single-row sections merged into one untitled card. Reuse the rows in
  `settings_widgets.dart` before inventing new ones.
- **No service layer.** As everywhere in the app, screens call `Client`
  directly (`setAvatar`, `changePassword`, `clearCache`).
- **Profile card** (`own_profile.dart`): it reads your name and picture from
  your own member state already in memory, falls back to a database-only
  lookup on a cold start, and redraws from `client.onRoomState`, so a rename
  in Account shows on return. It costs no request.
- **Device preferences** live in
  `lib/core/settings/app_preferences_provider.dart`: Riverpod notifiers over
  `shared_preferences`, per device and never synced. A setting that should
  follow the account to every device goes in Matrix account data under an
  `im.zuno.*` key instead, read and written through the SDK.
- **Links**: `lib/core/navigation/zuno_links.dart` holds the site addresses
  and `openLink`, which opens one in the browser or, failing that, shows the
  address in a snackbar. Google Play requires the privacy policy to be
  reachable inside the app.

## Decisions

- **Categories follow what people look for, not where the code lives.**
  Everything that costs bytes (media size, call data, caches) is in Data &
  storage, theme sits under Chats & calls, and diagnostics sit beside the
  version rows in About. A page that would hold only one or two rows is
  merged into another.
- **Sign out sits on the Settings root, not in an app-bar menu.** A menu
  would put the most destructive action in the app one tap from every
  screen, right beside the most routine one. Signing out is rare, so making
  it fast gains nothing, and a menu left holding only Settings has nothing to
  choose between: hence the plain icon.
- **The sign-out dialog depends on recovery.** Without a recovery code,
  signing out loses every room key held only on this device, and those
  messages become unreadable for good. That dialog says so and offers Set up
  recovery beside Sign out anyway. With recovery set up, it is an ordinary
  two-button confirmation. The sign-out sequence itself is in
  `authentication.md`.
- **Confirmed destructive actions read state in the tap handler**, not with
  `watch` in `build`. That avoids a needless rebuild dependency, and the
  widget test needs no provider overrides: a Cancel that ever reached the
  real action would throw instead of quietly signing a test client out.
- **Profile editing lives on the Account page itself**, not on a separate
  page, which saves a step for the most-touched settings.
- **Avatars shrink before upload** (`prepareAvatarPhoto`, shared with room
  avatars): GPS EXIF is dropped and the image is scaled down to avatar size.
  `setAvatar` uploads whatever it is given, so without this every client
  would fetch a full-size photo for an image only ever shown small. Any new
  avatar upload path must go through it too.
- **The typing toggle only stops sending.** You still see when others type.
- **Privacy and data-saving settings start on**: prevent accidental calls,
  reduce media size, use less data for calls, incognito keyboard, and
  prevent screenshots (Hide screen content on iOS). A default applies only
  while nothing is stored, so a choice someone made survives an update that
  changes the default.
- **Two cache actions, never merged**, because they cost different things.
  Clear cache drops stored messages and room state and forces a full resync.
  Clear media cache drops the attachment caches (memory and disk), the map
  tile cache and Flutter's image cache, with no server call.
- **Donation is one static About row** that opens the site's `#donate`
  anchor in the browser. It is never a prompt, badge or popup
  (`../brand-voice.md`), and there is no in-app payment. The URI must match
  the site's anchor.
- **Unbuilt settings ship as `ComingSoonTile` or `ComingSoonSwitchTile`
  rows in their final place**, never as ad hoc disabled widgets. Future scope
  stays visible, every placeholder looks the same, and each is easy to find
  when it is time to wire it up.
- **Enum settings follow `NotificationDeliveryMode`.** A stored value that
  is unknown, or that this platform does not offer, reads as the platform
  default, and storage is left untouched. Use this pattern for any setting
  with more than two states.
- **Options with their own sub-settings use a bottom-sheet picker** (the
  delivery-mode picker is the model), not a radio list. A radio list renders
  every option's sub-settings inline, which is mostly dead space for the
  options not chosen.
- **List pages keep their content while refreshing** (devices, key backup,
  push target). The centered spinner shows on the first load only. A failed
  first load says so and suggests pulling down, never "empty", and a failed
  refresh keeps the stale list.

## Platform differences

Rows that exist on one platform only are gated on
`platformCapabilitiesProvider` (`app-foundation.md`), never on a `Platform`
check, and a card with no applicable rows disappears. Notification rows are
gated the same way (`notifications.md`). The on-device protections this doc
owns share the "On this device" card in Security:

| Row | Capability | Android | iOS |
|---|---|---|---|
| Incognito keyboard | `keyboardLearningOptOut` | Turns off the keyboard's personalized learning in the composer | Hidden: iOS cannot ask a keyboard not to learn |
| Prevent screenshots | `screenSecurity` | `FLAG_SECURE`: blocks screenshots and recording, blanks Zuno in Recents | Shown as Hide screen content (`screenshotBlocking` is off) |

No iOS app can block a screenshot. Hide screen content instead covers Zuno
with the launch screen while the app is inactive (the app switcher, Control
Center, system prompts) and while the screen is recorded, mirrored or
shared, so Zuno stays unusable until the capture stops. A call's
picture-in-picture window hides its video too (`calls.md`).

## Planned, not built

**Profile visibility** would let someone choose who sees their name and
picture: everyone, people they share a room with, or direct chats only. It
goes in Account, right under the name and picture it governs, with a
pointer from Security. It needs a server module first. Synapse's own
profile controls (`include_profile_data_on_invite`,
`require_auth_for_profile_requests`) are server-wide, not per user, so the
module would read each user's choice from account data. A client-only
setting would enforce nothing. Still open: which tiers the server can truly
enforce, the default tier, and how it interacts with user-directory search
and the check that a profile exists.

## Gotchas

- **Security → Advanced is a disabled placeholder**, so
  `AdvancedSecurityPage` and everything on it is unreachable. Before wiring
  the row back, remove `TemporarySessionTokenTile`, a developer tool that
  signs in a second session without a refresh token and shows its access
  token. Advanced keeps protocol vocabulary on purpose
  (`security-verification.md`).
- **`readPreventScreenshots` is the one default** for both the provider and
  the cold-start call in `main.dart`. Change it there, never in one place
  only.
- **About's library versions are constants** in `about_page.dart`.
  `about_page_test.dart` reads `pubspec.lock` and fails when they drift, so a
  dependency upgrade ends with updating them.
- **`client.getUserProfile` serves a cached profile**, and `setProfileField`
  does not invalidate it. Account re-reads with `maxCacheAge: Duration.zero`
  after a save, or the old name comes back.
- **Riverpod 3 throws on `ref` once a page is gone.** After an `await`,
  check `mounted` before touching `ref`, or read what you need before
  awaiting.
- **Link previews has no row** while `linkPreviewsFeatureAvailable` is
  false. The provider stays, because the chat screen reads it.

## Testing

`expectEveryRowOnACard` (`test/helpers/card_layout.dart`) fails a row left
outside a card. `AboutPage.openUrl` is injectable, so tests assert the URI
and the not-opened snackbar without a platform channel.
