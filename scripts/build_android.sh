#!/usr/bin/env bash
# Builds the Android release: the APK people download from GitHub and the app
# bundle Google Play takes, both into build/release/.
#
#   VERSION=1.5.0 scripts/build_android.sh
#
# Neither is signed for release here. Without android/key.properties, Gradle
# signs with the debug key (android/app/build.gradle.kts), and the release
# workflow has no keystore on purpose: scripts/sign_release.sh signs both on
# the release manager's machine, so the key never reaches CI. A debug-signed
# APK installs, but it cannot update a release-signed one or open invite links
# (App Links verify the signature), so it is not something to hand out.
#
# rift-<version>-android.apk holds both ARM ABIs, and is the one the website
# offers: a person choosing between arm64-v8a and armeabi-v7a picks wrong.
# x86_64 is left out of it, since phones are ARM and it added 66 MB of
# libraries for emulators and a few Chromebooks. Beside it is one APK per ABI,
# x86_64's included, for whoever knows which they need. The bundle has all
# three, and Play hands each device only its own.
#
# Each single-ABI APK is its own build rather than Flutter's
# --split-per-abi, which numbers each ABI's APK differently (arm64-v8a's
# versionCode is 2000 + the build number). An install of one of those would
# refuse the full APK and Play's build as downgrades.
#
# Needs android/app/google-services.json (gitignored; the workflow writes it
# from a secret), without which the Google services plugin refuses to build.
set -euo pipefail
cd "$(dirname "$0")/.."

version=${VERSION:-$(sed -n 's/^version: //p' pubspec.yaml)}
version=${version%%+*}

[[ -f android/app/google-services.json ]] ||
  { echo "No android/app/google-services.json: the build needs it for push." >&2; exit 1; }

mkdir -p build/release
apk=build/app/outputs/flutter-apk/app-release.apk

for abi in arm64-v8a:android-arm64 armeabi-v7a:android-arm x86_64:android-x64; do
  flutter build apk --release --target-platform "${abi#*:}"
  cp -f "$apk" "build/release/rift-$version-android-${abi%%:*}.apk"
done

flutter build apk --release --target-platform android-arm,android-arm64
cp -f "$apk" "build/release/rift-$version-android.apk"

flutter build appbundle --release
cp -f build/app/outputs/bundle/release/app-release.aab "build/release/rift-$version-android.aab"
ls -l build/release/rift-"$version"-android*
