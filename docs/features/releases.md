# Releases

## Overview
Releases to Google Play and the App Store are automated. On the 1st of
each month, everything on `master` since the last release is tested,
built, signed, and submitted straight to production. Any failure stops
the release. Hotfixes run through the same pipeline when started by
hand. Commit subjects decide the version, and a draft file supplies the
store notes.

## Architecture
| File | Owns |
|---|---|
| `tool/release/release.dart` | Pure logic: versions, build numbers, commit types, notes limits, guards, rollout ladder |
| `tool/release/cli.dart` | The CLI the workflows call (`next`, `hotfix`, `guard`, `bump`, `check-notes`, `rollout`) |
| `tool/release/cut.sh`, `hotfix.sh` | The only code that pushes: release commit, `rc/X.Y.Z` branch, dispatch |
| `fastlane/Fastfile` | match signing, `supply`/`deliver` uploads, Play rollout steps |
| `.github/workflows/` | `cut-release` (cron 06:17 UTC on the 1st), `start-hotfix`, `release`, `advance-rollout` (daily 04:43 UTC) |

`release.yml` runs these steps in order:
1. Prepare.
2. Analyze, the Dart suite, Kotlin tests and Swift XCTests.
3. Android and iOS builds.
4. iOS upload, then Android upload.
5. Tag.

A failure opens an issue: a dispatched run's actor is the bot, so
GitHub emails nobody. The tag `vX.Y.Z` is pushed only after both
uploads.

## Decisions
- **Version:** minor if any `feat` since the highest tag, else patch if
  any `fix`, else no release. Major is manual. Every type in a combined
  subject (`chore: …; fix: …`) counts.
- **Build number:** MAJOR×1,000,000 + MINOR×1,000 + PATCH, the same on
  both stores. There's no store lookup, and only one build per version.
  A rejected binary ships as the next patch.
- **One branch per release, `rc/X.Y.Z`.** The branch name is the version.
  `pubspec.yaml` is bumped by the bot's `chore: release X.Y.Z` commit:
  on `master` for monthly cuts, on the rc branch for hotfixes.
- **Notes:** `docs/release-notes/next.txt` becomes
  `docs/release-notes/X.Y.Z.txt` at the cut. It must be non-empty and
  ≤ 500 characters (Play's limit).
- **iOS uploads first.** An App Store submission can be withdrawn; a Play
  production commit can only be halted. `reject_if_possible` lets a
  hotfix replace a version still in review.
- **Play's staged rollout** climbs Apple's phased ladder, one step a day:
  1, 2, 5, 10, 20, 50, 100%. It's stateless and leaves halted releases
  alone.
- **Runners are pinned, never `-latest`:** `ubuntu-24.04`, plus the
  `xcode-27` image with Xcode `27.0`, the same build used locally. A
  label migration then can't change the release toolchain without
  warning. Moving to a new image is a deliberate change, made after a
  green dry run.

## Gotchas
- **`feat` must mean user-facing.** Tooling uses `chore`, or it forces a
  minor release.
- **A hotfix restores `next.txt` from the base tag, and records
  `(cherry picked from commit …)`.** `next` skips master commits named in
  such a trailer, so cherry-pick onto an rc with `-x`. After a hotfix
  ships, remove its line from `next.txt`.
- **Re-running a failed upload is safe.** If Apple already holds build N,
  the iOS lane submits it without re-uploading.
- **Swift XCTests run serially** (`-parallel-testing-enabled NO`).
  Parallel clone simulators cold-start the notification daemon past the
  tests' 60 s.
- **CI writes the gitignored inputs from secrets** (`DOTENV`,
  `GOOGLE_SERVICES_JSON`, the keystore) and fails if they're missing.
  Without `google-services.json`, the AAB builds green and ships
  without FCM.
- **The iOS jobs need the Xcode 27 SDK.** `MetricsSubscriber` uses
  `MetricManager`, which is behind `#available(iOS 27.0, *)`, but the
  type still has to exist at compile time. The `macos-26` image tops
  out at Xcode 26.6 and fails to compile it. `xcode-27` is a GitHub
  preview image, so expect occasional queueing.
- **GITHUB_TOKEN can't push changes to `.github/workflows/`,** so a
  hotfix touching a workflow fails at the push.
- **A public repo disables scheduled workflows after 60 days** with no
  commits.
- **Only one run per concurrency group can wait.** A third queued run
  silently cancels the pending one.
- **`v1.3.0` predates the pipeline.** Hotfixes need a base tag containing
  `release.yml`.

## Testing
- `test/tool/release/` covers the logic, the CLI (against temp git repos)
  and both scripts (against a temp bare remote with a fake `gh`).
- **Dry run:** dispatch `release` on `rc/dry-run` with `dry_run`. It runs
  the full gate, both signed builds, an App Store `verify_only` check
  and a Play `validate_only` upload. No tag.
