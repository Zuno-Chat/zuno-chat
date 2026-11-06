# zuno_emoji

Internal Flutter package for the Zuno app: the emoji picker, its emoji data
(generated from Unicode and CLDR), search in the app's languages, recent emoji
and skin tones, and a check of which emoji Flutter can draw on the device. Not
published.

Regenerate the data after bumping the pinned Unicode or CLDR version in
`tool/generate.dart`:

```
dart run tool/generate.dart
```
