# Excluded features

These are ruled out for good, not deferred. Do not re-propose one unless
asked. If one is reconsidered, move it out of here and into the feature doc
that takes it on.

- **SSO/OIDC.** The homeserver does not support it.
- **Threads.**
- **Custom status message.**
- **App lock (PIN or biometric on open).**
- **Room search in the chat list.** It is not needed at a personal client's
  room count.
- **Sticky timeline date pill**: a copy of the day's date that stays at the
  top of the timeline while scrolling, replaced when the next day's divider
  reaches it. The plain inline date dividers are the whole feature.
- **Anything admin-facing.** Nothing in the app is admin-facing: it calls no
  admin endpoint and keeps the server out of view
  (`../features/rooms-membership.md`, `../brand-voice.md`). That rules out:
  - **Admin detection**, such as a "homeserver admin" badge. It needs
    Synapse's proprietary admin API, and it would gate nothing, since the
    app has no admin actions.
  - **A homeserver information screen** (host, spec and room versions,
    upload limit, feature probes). It would be the one screen that shows the
    server.
  - **Call provider settings in `.well-known`.** A document anyone can fetch
    without auth could carry only the provider's non-secret app ID, never a
    credential. The `zuno_calls` Synapse module holds the app ID and
    credentials server-side instead (`../features/calls.md`).
- **Bots and bridges.**
- **Third-party widgets** (Jitsi, polls and the like).
- **Multi-account switching.**
