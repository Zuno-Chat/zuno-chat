#!/usr/bin/env bash
set -euo pipefail

main() {
  local tool
  tool=$(mktemp -d)
  cp "$(dirname "$0")"/*.dart "$tool"/
  release() { dart "$tool/cli.dart" "$@"; }

  local version
  version=$(release waiting)
  if [ "$version" = none ]; then
    echo "No release is waiting; nothing to ship."
    return 0
  fi

  gh workflow run release.yml --ref "rc/$version"
  echo "Shipping rc/$version."
}

main "$@"
