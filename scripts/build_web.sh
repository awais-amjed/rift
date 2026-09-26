#!/usr/bin/env bash
# Build the web app, with the worker that encrypts its calls.
#
# Calls are end-to-end encrypted, and in a browser LiveKit does that in a web
# worker it loads from /e2ee.worker.dart.js. `flutter build web` does not make
# that file, and without it a call sits on "Connecting…" forever. The worker
# is compiled from the livekit_client this project resolves, so it cannot
# drift from the package it has to talk to; it is not committed for the same
# reason.
#
#   scripts/build_web.sh           # worker, then `flutter build web --release`
#   scripts/build_web.sh --worker  # worker only, before `flutter run -d chrome`
#
# Extra arguments go to `flutter build web`.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter pub get >/dev/null
livekit=$(python3 -c '
import json
for p in json.load(open(".dart_tool/package_config.json"))["packages"]:
    if p["name"] == "livekit_client":
        print(p["rootUri"].removeprefix("file://"))
')
dart compile js "$livekit/web/e2ee.worker.dart" \
  --packages=.dart_tool/package_config.json \
  -o web/e2ee.worker.dart.js -m
rm -f web/e2ee.worker.dart.js.deps web/e2ee.worker.dart.js.map

[[ ${1:-} == --worker ]] && exit 0
flutter build web --release "$@"
