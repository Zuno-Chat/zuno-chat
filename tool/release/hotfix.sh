#!/usr/bin/env bash
set -euo pipefail

main() {
  : "${NOTES:?NOTES is required}"
  : "${COMMITS:?COMMITS is required}"
  local tool
  tool=$(mktemp -d)
  cp "$(dirname "$0")"/*.dart "$tool"/
  release() { dart "$tool/cli.dart" "$@"; }

  local plan version base
  plan=$(release hotfix)
  read -r version base <<<"$plan"
  local branch="rc/$version"

  if git ls-remote --exit-code --heads origin "$branch" >/dev/null; then
    echo "$branch already exists. Finish or delete it first." >&2
    return 1
  fi
  if ! git cat-file -e "$base:.github/workflows/release.yml" 2>/dev/null; then
    echo "$base predates the release pipeline; hotfix it by hand." >&2
    return 1
  fi

  printf '%s\n' "$NOTES" >"$tool/notes.txt"
  release check-notes "$tool/notes.txt"

  local input commit picks=()
  for input in $COMMITS; do
    commit=$(git rev-parse --verify --quiet "$input^{commit}") || commit=
    if [ -z "$commit" ] || ! git merge-base --is-ancestor "$commit" origin/master; then
      echo "$input is not on master. Land the fix on master first." >&2
      return 1
    fi
    picks+=("$commit")
  done

  local draft=docs/release-notes/next.txt
  git switch --quiet --create "$branch" "$base"
  for commit in "${picks[@]}"; do
    git cherry-pick --no-commit "$commit" >/dev/null 2>&1 || true
    git checkout --quiet "$base" -- "$draft"
    if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
      git reset --quiet --hard HEAD
      echo "$commit does not apply cleanly on $base. Resolve it by hand on $branch." >&2
      return 1
    fi
    if git diff --cached --quiet; then
      continue
    fi
    {
      git log -1 --format=%B "$commit"
      printf '\n(cherry picked from commit %s)\n' "$commit"
    } >"$tool/message"
    git commit --quiet --file "$tool/message" --author "$(git log -1 --format='%an <%ae>' "$commit")"
  done

  mkdir -p docs/release-notes
  cp "$tool/notes.txt" "docs/release-notes/$version.txt"
  release bump "$version"
  git add pubspec.yaml "docs/release-notes/$version.txt"
  git commit --quiet --message "chore: release $version"
  git push --quiet origin "$branch"
  gh workflow run release.yml --ref "$branch"
  echo "Started $branch."
}

main "$@"
