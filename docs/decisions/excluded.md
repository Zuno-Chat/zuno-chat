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
- **Sticky timeline date pill**, a date that stays at the top while
  scrolling. The plain inline date dividers are the whole feature.
- **Anything admin-facing.** The app calls no admin endpoint and keeps the
  server out of view (`../features/rooms-membership.md`,
  `../brand-voice.md`). That rules out:
  - **Admin detection**, such as a "homeserver admin" badge. It needs
    Synapse's proprietary admin API and would gate nothing.
  - **A homeserver information screen.** It would be the one screen that
    shows the server.
  - **Call provider settings in `.well-known`.** A public document could
    never carry a credential, so the `zuno_calls` Synapse module holds them
    server-side instead (`../features/calls.md`).
- **Bots and bridges.**
- **Third-party widgets** (Jitsi, polls and the like).
- **Multi-account switching.**
