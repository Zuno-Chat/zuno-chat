# Push and call ring

With Zuno closed, a call rings from a server-sent push on both platforms (a PushKit VoIP push on iOS, an FCM data push on Android), while a running app still rings from sync. Messages keep `event_id_only` alert pushes: on iOS a read-only notification service extension (NSE) fetches and decrypts their content, on Android Dart does, and only Android waits for a late message key, briefly. The mechanics are in `../features/notifications.md` (push, the extension, the `zuno_push` contract) and `../features/calls.md` (the ring).

- **Ring from the server.** A ring read from the call's message needs that message's room key, so a late key turned an Android call into "New message" and then "Missed call", and Apple reserves the NSE ring API, behind the filtering entitlement, for servers that cannot tell a call from a message. A server running `zuno_push` can: the Synapse module watches `m.call.member`, which is clear state, and sends through stock Sygnal. A server ring needs no room keys or entitlement, and on iOS no notification permission.
- **One ring decision for both platforms.** The module decides with Synapse's own power-level and push-rule evaluation, so a server ring follows the same permissions and mute settings as any push. A hand-written check would drift, missing room-v12 creators (every new Zuno DM) and mute settings changed in other clients.
- **Rings are sent at least once.** The module re-sends a ring that a crash interrupted, and the device drops duplicates by call.
- **One sealed, fixed-size ring payload under a per-device key**, the same format on both platforms, so Apple and Google learn only that a call arrived. The key id and expiry stay in clear, so the device can drop a stale ring before opening it, on iOS even before first unlock.
- **Android opens the payload in Kotlin with the platform's ChaCha20-Poly1305**, under a key wrapped by an Android Keystore key, because the Keystore cannot hold ChaCha keys and Dart has no opener; the platform cipher needs Android 9, so Android 8.x keeps ringing from the call's message.
- **Android rings natively at once**, from the push receiver, before any Dart runs, so a ring never waits behind a message push or a cold Flutter start. Its rules mirror iOS's `RingDecision`, and Dart adopts the ring afterwards, as it adopts CallKit's native ring on iOS.
- **An Android push waits briefly for a late message key.** A message push that cannot decrypt waits, until a deadline counted from its arrival, for at most two syncs, then shows "New message" and reports done, because the key usually lands in the catch-up sync just behind the fetch, while a retry after the reply died with the frozen or reclaimed process. The deadline counts from arrival so pushes queued behind one another never stack their waits.
- **A fetching, read-only NSE** on iOS. It fetches the pushed event with a narrow module credential and decrypts it with trimmed Megolm sessions the app exports to an App Group only the two share. It never holds a Matrix token, the Olm identity or `zuno.db`.
- **Names, never silence.** A message the NSE cannot decrypt, or a reply that did not come from the module, still shows its sender and room. A call whose iOS ring failed becomes a time-sensitive fallback notification.
- **Private by default.** One preview level drives notification text and the ring's name, because the OS keeps what a notification showed. Thread ids and the call handle are opaque, and there are no Siri donations. iOS notifications are text only, since images would add a zero-click attack surface. Message pushes still show Apple the room and event ids that stock Sygnal adds.
- **Constraint.** The ring depends on `m.call.member` staying clear state. Encrypted or sticky call membership would need an explicit ring endpoint.

## Accepted costs

- iOS rings calls even when notifications are denied: calls are not notifications, and PushKit needs no permission.
- At preview Nothing the NSE fetches nothing, so a failed iOS ring gets no fallback.
- A room read elsewhere while Zuno is closed keeps its iOS badge until the next push or open, because receipt badge pushes are off.
- After a sender's key changes, their messages show names only on iOS until Zuno is opened.
- An iOS app not opened for 30 days has an expired credential, so its notifications show names only until the next open.
- On Android, a message whose key arrives after the deadline stays "New message" until Zuno is next opened.
- On Android, a readable push queued behind a locked one shows its text only once the locked one's wait ends, since pushes reach Dart one at a time; the instant notice still lands at once.
- Android 8.x and UnifiedPush still ring from the call's message, so a late key there still misses the ring; UnifiedPush would need the module to post the payload to the distributor.
- A stale Android ring push shows nothing, which FCM counts against the app's high-priority use, so the module never sends a ring it knows is stale.

## Rejected

- **Ringing from the NSE.** The entitlement is scoped to servers that cannot tell a call, the API shares PushKit's kill counter, and an NSE does not run while notifications are off.
- **The PushKit token as a Matrix pusher.** Every notifying event would become a VoIP push, and iOS requires each VoIP push to report a call.
- **`on_new_event` as the trigger.** It makes Synapse load full room state for every event on every worker.
- **`zuno.db` in the NSE.** A file lock held at suspension gets the process killed, and every key would be within the NSE's reach.
- **A Matrix token in the NSE.** A second token refresher logs the app out, and longer token lifetimes would change Android too.
- **Dart or the full SDK in the NSE.** They do not fit the extension's memory limit.
- **A plaintext ring payload.** It hands Apple or Google the room, the call and the video flag.
- **A to-device key peek.** It would put the phone's Olm channels, or its device identity, in the process most exposed to hostile input.
- **The NSE as its own Matrix device.** Every sender would have to share keys with one more device per user.
- **Background refresh to fetch keys.** It runs near the user's own app opens and never after a force-quit.
- **Sygnal badge counts.** Receipt badge pushes tell Apple when rooms are read, and a stored +1 badge never decrements.
- **A custom push gateway, relay or direct APNs or FCM sender.** Sygnal stays stock.
