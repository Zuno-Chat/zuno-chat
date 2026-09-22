# Release signing

Release builds are signed with a keystore this repository does not contain.
Without `android/key.properties` a release build still succeeds, but falls
back to the **debug** key and prints a warning — see
`android/app/build.gradle.kts`.

That fallback is for local convenience only. The Android debug key ships
with the SDK, is identical on every developer machine on earth, and its
password is `android`. An APK signed with it can be replaced by anyone with
an in-place update that inherits the app sandbox — the Matrix database,
the access token, and every Megolm key in it. Never distribute one.

## Creating the keystore

```
keytool -genkey -v -keystore ~/zuno-release.jks \
  -keyalg RSA -keysize 4096 -validity 10000 -alias zuno
```

Then create `android/key.properties` (gitignored):

```
storeFile=/absolute/path/to/zuno-release.jks
storePassword=…
keyAlias=zuno
keyPassword=…
```

## Keeping it

The keystore is not recoverable. Losing it means no future build can ever
update an existing install — every user has to uninstall and lose their
local data. Back it up somewhere durable and offline, separately from the
passwords.

Do not commit either file. `.gitignore` covers `android/key.properties`,
`*.jks` and `*.keystore`, but that is a safety net, not a substitute for
keeping them outside the working tree.
