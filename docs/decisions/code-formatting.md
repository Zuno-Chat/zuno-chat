# Code formatting

Formatters own the layout of every source file; nothing is formatted by hand.

| Language | Tool | Style | Config |
|---|---|---|---|
| Dart | `dart format` | tall style, 80 columns, automatic trailing commas | `formatter:` in each `analysis_options.yaml` |
| Kotlin | ktlint 1.8 (Homebrew) | `android_studio`, 100 columns, trailing commas kept | `.editorconfig` |
| Swift | swift-format (ships with Xcode) | swift-format defaults: 2-space indent, 100 columns | `.swift-format` |

- **Why these styles**: each is its ecosystem's default and was the closest match to the existing code, so adopting it caused the least churn. `ktlint_official` doubled the Kotlin diff. `android_studio` strips trailing commas unless the `ij_kotlin_allow_trailing_comma*` flags are set, and the code relies on them.
- **Dart lints for what the formatter skips**: `prefer_single_quotes`, `directives_ordering`, `prefer_relative_imports`.
- **Rejected**:
  - Dart `trailing_commas: preserve`: it still left files drifting, and it departs from the default.
  - The `require_trailing_commas` lint: it is incompatible with tall style.
- **`package-name` is off for `packages/**` Kotlin**: a plugin's underscored package name is fixed by its Flutter plugin identity.
- **Checking the tree**:
  - Dart: `dart format --output=none --set-exit-if-changed lib test packages`. Never run `dart format .` from the root, because it reaches into `build/` caches.
  - Kotlin: `ktlint` on the tracked `*.kt` and `*.kts` files.
  - Swift: `xcrun swift-format lint -r ios/Runner`.
- **No gate yet**: neither CI nor the commit routine checks formatting.
