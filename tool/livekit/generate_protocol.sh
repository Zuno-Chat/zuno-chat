#!/usr/bin/env bash
set -euo pipefail

PROTOCOL_TAG="v1.53.2"
PROTOC_PLUGIN_VERSION="25.1.0"

usage() {
  echo "Regenerates lib/core/calls/livekit/proto from livekit/protocol $PROTOCOL_TAG."
  echo "Needs: brew install protobuf"
  echo "       dart pub global activate protoc_plugin $PROTOC_PLUGIN_VERSION"
  echo "Run: tool/livekit/generate_protocol.sh"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

export PATH="$PATH:$HOME/.pub-cache/bin"
for tool in protoc protoc-gen-dart git dart; do
  command -v "$tool" >/dev/null || { usage >&2; exit 1; }
done

dart pub global list | grep -qxF "protoc_plugin $PROTOC_PLUGIN_VERSION" || {
  usage >&2
  exit 1
}

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

out="lib/core/calls/livekit/proto"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git clone --quiet --depth 1 --branch "$PROTOCOL_TAG" \
  https://github.com/livekit/protocol "$work/protocol"

rm -rf "$out"
mkdir -p "$out"
protoc --dart_out="$out" \
  -I "$work/protocol/protobufs" \
  livekit_rtc.proto livekit_models.proto livekit_metrics.proto
find "$out" -name '*.pbjson.dart' -delete
dart format "$out" >/dev/null
