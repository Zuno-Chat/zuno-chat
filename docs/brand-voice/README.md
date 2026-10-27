# Brand voice

Zuno sounds like a quiet neighbor: minds its own business, is there when
needed, and looks out for you. Plain, calm and principled, never loud.

**Tagline:** Messages that stay between you two.

## Why Zuno exists

- **A safe place for your people.** Friends and family talk without being watched.
- **Privacy without effort.** Strong protection that feels like any chat app.
- **Free and open source.** Built in the open and free for anyone to use, with
  no ads and no tracking. This is the core identity: state it as fact, never
  as a boast or a plea.
- **An app, not a service.** Zuno connects to any Matrix server. zuno.chat is
  one server among many, never the product.

## Audience

Everyday people, not privacy experts. After a week, they should be at ease
and stop wondering who is reading. The site and store listing also speak to
people who run a server for their family, friends or community.

## Traits

| Trait | Means | Does not mean |
|---|---|---|
| Honest | States limits and trade-offs unprompted | Caveats buried in fine print |
| Protective | Stops people before a mistake they cannot undo | Nagging about routine actions |
| Confident | Says it once, without hedging | Superlatives or bravado |
| Minimal | The fewest words that do the job | Dropping the next step or a consequence |
| Defiant | Plainly refuses ads and tracking | Outrage or attacks on others |
| Reassuring | Explains why something that looks scary is fine | Hiding a real risk |

When traits pull apart:

- **Protective vs at ease:** firm tone only before something irreversible or
  that could cost someone their messages. Everything else stays calm.
- **Minimal vs honest:** never cut a limit or a consequence to save words.
- **Defiant vs matter-of-fact:** defiance shows in what Zuno refuses to do,
  not in adjectives.

## Mechanics

- American English. Sentence case for titles and buttons.
- Each translation follows `translating.md` and its own guide in this folder.
- No contractions: "cannot", "you are", "it is".
- No emoji and no exclamation marks, anywhere.
- No speaker: never "we" or "I". Say "Zuno" or rephrase.
- The name is "Zuno". "Zuno Chat" only where a store listing requires it.
- Never name other apps. Refer to them generally ("many chat apps") at most.
- Technical terms are fine (encryption, verification, recovery code). Use them precisely.
- Buttons name the action: "Delete account", not "OK" or "Yes".

## Words

| Use | Not |
|---|---|
| chat (one-to-one) | conversation, DM |
| room (group) | group, channel, space |
| community (a group of rooms) | space, server, workspace |
| device | session, phone, client |
| recovery code | recovery key, security key, passphrase |
| sign in, sign out | log in, log out |

The app avoids the server: name it only where a privacy point, or who sends
or receives something, depends on it. Zuno is the app, never the server: the
server sends sign-up codes and receives reports. Matrix never appears in the
app.

## Claims and limits

- Absolutes only where the design guarantees them. Never "100% secure",
  "unhackable" or "military-grade".
- Accounts belong to the server. Zuno never asks for a phone number: sign-up
  is a username and a password, and where the server sends a sign-up code,
  the email address is used only for that code and is not stored with the
  account. Pair it with its limits: a username containing a real name still
  identifies someone, and there is no email to reset a lost password.
- Name limits where they matter, unprompted. Encryption protects what people
  say. It does not hide that they talked, and it cannot stop a screenshot or
  a compromised device.
- Wherever calls or notifications are promised, say they need a server set up
  for Zuno, such as zuno.chat.
- Matrix appears on the site and store listing only: as what Zuno connects
  to, and as the reason the encryption can be trusted.

## By surface

| Surface | Voice |
|---|---|
| App | Plainest. No dry edge. Avoid the server; never Matrix. Sign-up never suggests a phone number is needed; an email address appears only at the sign-up code step, with its one purpose stated. |
| Notifications | Shortest. Messages, calls and invites only; never to pull people back in. |
| Site and store listing | Lead with what Zuno is, matter-of-fact. A dry line allowed, sparingly. Free and open source, any Matrix server and encryption by default are the story; zuno.chat is one place to make an account, never the product. |
| Support and social | Same rules. Answer in the first sentence. |

## By moment

**Pitch.** Say what Zuno is as fact, then what it lets people do.
- Write: "Zuno is a free, open-source chat app. It works with any Matrix server: zuno.chat, the one your friends already use, or your own."
- Not: "Big tech is spying on you. Take back your privacy!"

**Dry edge** (site and social only). Understated, never at someone's expense.
- Write: "Your messages are none of your server's business."
- Not: "Unlike those other apps, this one actually respects you."

**Error.** What happened, then what to do. No apology, no blame, no raw error text.
- Write: "Message not sent. Check your connection and try again."
- Not: "Oops, something went wrong: SocketException"

**Irreversible or risky.** Firm. Name the action and the consequence, and say
that nobody can undo it. The button repeats the action.
- Write: "Save your recovery code" / "If you lose this code and all your signed-in devices, your message history is gone. Nobody can restore it for you." / "Save code"
- Not: "Keep this safe!" / "OK"

**Reassurance.** What is happening, why it is fine, and the fix if there is one.
- Write: "Sent before this device signed in. Approve this device from another one to read it."
- Not: "Unable to decrypt message."

**Success.** A short, flat confirmation in past tense.
- Write: "Password changed."
- Not: "Awesome, your password was successfully updated."

**Donation** (app). One static line in Settings. Never a prompt, badge or popup.
- Write: "Donations help pay for building Zuno."
- Not: "Enjoying Zuno? Support us today."

**Release notes** (store "What's new"). Features under "New", one bullet
each, saying what the reader can now do, never how. Fixes are not listed,
only counted in one closing line ("Fixed 1 bug." for one). Leave out
whichever part is empty.
- Write:
  ```
  New
  • Picture-in-picture for iPhone video calls.

  Fixed 3 bugs.
  ```
- Not: "Bug fixes and performance improvements." / "• Closing picture-in-picture ending the call." / "• Picture-in-picture through AVPictureInPictureController."
