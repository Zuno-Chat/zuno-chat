# Settings

Settings is the app's one place for account and app preferences, opened from
a plain settings icon in the room list app bar. This doc owns the shell, its
categories and the settings no other feature owns. A feature's own settings
are documented with that feature.

| Category | Holds | Behavior documented in |
|---|---|---|
| Account (the profile card) | Picture, display name, username, change password | here; password in `authentication.md` |
| Notifications | Enable, notify-for, sounds, content (iOS), Delivery (Android), Diagnostics hub | `notifications.md` |
| Chats & calls | Theme, typing indicator, prevent accidental calls | here; accidental calls in `calls.md` |
| Data & storage | Reduce media size, less data for calls, clear cache, clear media cache | here; `chats-messaging.md`, `calls.md` |
| Security | Status, recovery, devices, blocked people, on-device protections, Advanced | `security-verification.md`; blocked people in `rooms-membership.md`; on-device protections here |
| About | Versions, donate (Android), privacy policy, terms, source, licenses, crash reports, hidden messages | here; `crash-reporting.md`, `chats-messaging.md` |

The root opens with the profile card, which leads to Account. Below the
categories sit Send feedback (`crash-reporting.md`), then Sign out and
Delete account (`authentication.md`).

## Architecture

- **Pages** live in `lib/features/settings/presentation/`, one per category,
  each a `CardListView` of `CardGroup`s (`app-foundation.md`).
- **The profile card** (`own_profile.dart`) reads your name and picture from
  your own member state in memory, so it costs no request.
- **Device preferences** are Riverpod notifiers over `shared_preferences`
  (`app_preferences_provider.dart`), per device and never synced. A setting
  that should follow the account to every device goes in Matrix account data
  under an `im.zuno.*` key instead.
- **Links** go through `zuno_links.dart`. Google Play requires the privacy
  policy to be reachable inside the app.

## Decisions

- **Categories follow what people look for, not where the code lives.**
  Everything that costs bytes is in Data & storage, theme sits under Chats &
  calls, and a page that would hold only one or two rows is merged into
  another.
- **Sign out sits on the Settings root, not in an app-bar menu**, which would
  put the most destructive action one tap from every screen.
- **The sign-out dialog depends on recovery.** Without a recovery code,
  signing out loses every room key held only on this device, so the dialog
  says so and offers Set up recovery. The sign-out sequence itself is in
  `authentication.md`.
- **Avatars shrink before upload** (`prepareAvatarPhoto`, shared with room
  avatars): GPS EXIF is dropped and the image is scaled to avatar size. Any
  new avatar upload path must go through it too.
- **Privacy and data-saving settings start on**: prevent accidental calls,
  reduce media size, use less data for calls, incognito keyboard, and
  prevent screenshots. A default applies only while nothing is stored, so a
  choice someone made survives an update that changes the default.
- **Two cache actions, never merged**, because they cost different things.
  Clear cache drops stored messages and room state and forces a full resync.
  Clear media cache drops the attachment, map tile and image caches, with no
  server call.
- **Donation is one static About row** that opens the site in the browser.
  It is never a prompt, badge or popup (`../brand-voice.md`), and there is
  no in-app payment.
- **iOS has no Donate row**, because the App Store forbids linking out to
  pay the developer. The rule is one capability for the whole platform, not
  per storefront, so the iOS app is the same in every region.
- **Unbuilt settings ship as `ComingSoonTile` or `ComingSoonSwitchTile`
  rows in their final place**, so future scope stays visible and every
  placeholder looks the same.
- **Enum settings follow `NotificationDeliveryMode`.** A stored value that is
  unknown, or that this platform does not offer, reads as the platform
  default without touching storage.

## Platform differences

Rows that exist on one platform only are gated on
`platformCapabilitiesProvider` (`app-foundation.md`), and a card with no
applicable rows disappears. The on-device protections this doc owns share
the "On this device" card in Security:

| Row | Android | iOS |
|---|---|---|
| Incognito keyboard | Turns off the keyboard's personalized learning in the composer | Hidden: iOS cannot ask a keyboard not to learn |
| Prevent screenshots | `FLAG_SECURE`: blocks screenshots and recording, blanks Zuno in Recents | Shown as Hide screen content |

No iOS app can block a screenshot. Hide screen content instead covers Zuno
with the launch screen while the app is inactive and while the screen is
recorded, mirrored or shared.

## Planned, not built

**Profile visibility** would let someone choose who sees their name and
picture. It needs a server module first, because Synapse's own profile
controls are server-wide and a client-only setting would enforce nothing.

## Gotchas

- **Security → Advanced is a disabled placeholder.** Before wiring it back,
  remove `TemporarySessionTokenTile`, a developer tool that shows an access
  token.
- **`readPreventScreenshots` is the one default** for both the provider and
  the cold-start call in `main.dart`, so change it there only.
- **About's library versions are constants** that `about_page_test.dart`
  checks against `pubspec.lock`, so a dependency upgrade ends with updating
  them.
- **`client.getUserProfile` serves a cached profile** that
  `setProfileField` does not invalidate, so Account re-reads with
  `maxCacheAge: Duration.zero` after a save.
- **Riverpod 3 throws on `ref` once a page is gone**, so check `mounted`
  after an `await` before touching `ref`.
- **`expectEveryRowOnACard`** (`test/helpers/card_layout.dart`) fails a test
  for any row left outside a card.
