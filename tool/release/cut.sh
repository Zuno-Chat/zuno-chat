#!/usr/bin/env bash
set -euo pipefail

main() {
  local tool
  tool=$(mktemp -d)
  cp "$(dirname "$0")"/*.dart "$tool"/
  release() { dart "$tool/cli.dart" "$@"; }

  local version
  version=$(release next)
  if [ "$version" = none ]; then
    echo "No feat or fix since the last release; nothing to cut."
    return 0
  fi

  local draft=docs/release-notes/next.txt
  local notes="docs/release-notes/$version.txt"
  local branch="rc/$version"
  if [ ! -f "$notes" ]; then
    if git ls-remote --exit-code --heads origin "$branch" >/dev/null; then
      echo "$branch exists but was never cut from master. Delete it to re-cut: git push origin --delete $branch" >&2
      return 1
    fi
    release check-notes "$draft"
    git mv "$draft" "$notes"
    : >"$draft"
    release bump "$version"
    git add pubspec.yaml docs/release-notes
    git commit --quiet --message "chore: release $version"
    git push --quiet origin HEAD:master
  elif [ -s "$draft" ]; then
    echo "$version was already cut, but $draft has new notes. Move them into $notes, then re-run." >&2
    return 1
  fi

  local remote
  remote=$(git ls-remote --heads origin "$branch" | cut -f1)
  if [ -z "$remote" ]; then
    git push --quiet origin "HEAD:refs/heads/$branch"
  elif [ "$remote" != "$(git rev-parse HEAD)" ]; then
    echo "$branch exists at $remote, not at master's HEAD. Delete it to re-cut: git push origin --delete $branch" >&2
    return 1
  fi

  gh workflow run release.yml --ref "$branch"
  echo "Cut $branch."
}

main "$@"
