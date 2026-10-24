#!/usr/bin/env bash
# Signs a release's update feeds, which is what lets installed copies of Rift
# update to it.
#
#   scripts/sign_release.sh v1.5.0         # the GitHub release of that tag
#   scripts/sign_release.sh v1.5.0 --play-notes FILE   # ...and its bundle to Google Play
#   scripts/sign_release.sh --dir DIR      # the feeds in a folder (testing)
#   scripts/sign_release.sh --android DIR  # the APKs and bundles in a folder
#   scripts/sign_release.sh --announce v1.5.0   # only post the announcement
#   scripts/sign_release.sh --announce v1.5.0 discord   # ...to one place only
#
# The release workflow publishes each feed (releases.win.json and
# releases.linux.json) without a signature, and Rift skips a feed it cannot
# verify — so until this runs, nobody is offered the release. It shows what
# each feed offers, signs it with the release key from the keyring
# (scripts/release_key.sh), checks the signature, and uploads
# releases.<channel>.json.sig beside it.
#
# The message signed is "rift-update-feed-v1\n<channel>\n" followed by the
# feed's bytes, as rust/src/updater/signature.rs checks it.
#
# Once both are signed it posts the release's notes to a Rift channel through
# a webhook, betas included: signing, not publishing, is when people can have
# it. The webhook's URL holds its secret, so it lives in the keyring
# (`secret-tool store --label='Rift release webhook' service
# rift-release-webhook`), and without one nothing is posted. The same notes go
# to a Discord channel through its webhook, kept the same way under
# `service rift-discord-webhook`.
#
# The workflow keeps the Android APK and app bundle with its run instead of
# publishing them, signed only with the debug key. This downloads them, signs
# them with the keystore android/key.properties names, attaches the APKs to
# the release and leaves the bundle in build/release/ for Google Play, where
# the keystore is only the upload key (RELEASING.md). Given --play-notes
# (Play's "What's new", see scripts/play_upload.sh), it also puts the bundle
# on Play: a beta on open testing, a release on production as a draft.
set -euo pipefail
cd "$(dirname "$0")/.."

repo=awais-amjed/rift
channels=(win linux)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

sign_feed() {
  local channel=$1 feed=$2
  { printf 'rift-update-feed-v1\n%s\n' "$channel"; cat "$feed"; } >"$work/message"
  scripts/release_key.sh public >/dev/null
  if [[ -n ${RIFT_RELEASE_KEY_FILE:-} ]]; then
    cp "$RIFT_RELEASE_KEY_FILE" "$work/key.pem"
  else
    secret-tool lookup service rift-release-key >"$work/key.pem"
  fi
  openssl pkeyutl -sign -rawin -inkey "$work/key.pem" -in "$work/message" -out "$work/signature"
  openssl pkey -in "$work/key.pem" -pubout -out "$work/public.pem"
  rm "$work/key.pem"
  openssl pkeyutl -verify -rawin -pubin -inkey "$work/public.pem" \
    -in "$work/message" -sigfile "$work/signature" >/dev/null
  openssl base64 -A -in "$work/signature" >"$feed.sig"
}

# The release workflow's run for [tag]: where the Android build waits.
fetch_android() {
  local tag=$1 run kept
  run=$(gh run list -R "$repo" -w release.yml -b "$tag" -e push -s success -L 1 \
    --json databaseId --jq '.[0].databaseId // empty')
  [[ -n $run ]] || return 1
  # A run that kept no build, or whose build has expired, has nothing to sign.
  # One that kept it but would not download stops everything: skipped, the
  # feeds were signed and announced without the APKs (1.5.1-beta.4).
  kept=$(gh api "repos/$repo/actions/runs/$run/artifacts" \
    --jq '.artifacts[] | select(.name == "android" and (.expired | not)) | .id')
  [[ -n $kept ]] || return 1
  gh run download "$run" -R "$repo" -n android -D "$work/android" && return 0
  echo "android: run $run kept a build but it did not download; nothing signed, try again" >&2
  exit 1
}

# The keystore android/key.properties names, its passwords handed to the tools
# in the environment rather than on a command line, where ps shows them.
read_keystore() {
  local key value
  while IFS='=' read -r key value; do
    value=${value%$'\r'}
    case ${key// /} in
      storeFile) keystore=$value ;;
      keyAlias) key_alias=$value ;;
      storePassword) export RIFT_STORE_PASS=$value ;;
      keyPassword) export RIFT_KEY_PASS=$value ;;
    esac
  done <android/key.properties
  # Gradle reads a relative one from the app module.
  [[ $keystore == /* ]] || keystore=android/app/$keystore
  [[ -f $keystore ]] || { echo "android: no keystore where android/key.properties says" >&2; exit 1; }
}

# apksigner from the newest build tools, and the JDK Flutter builds with when
# none is on the PATH (Android Studio's).
android_tools() {
  local sdk
  sdk=$(sed -n 's/^sdk\.dir=//p' android/local.properties 2>/dev/null)
  sdk=${sdk:-${ANDROID_HOME:-$HOME/Android/Sdk}}
  apksigner=$(ls -d "$sdk"/build-tools/*/ | sort -V | tail -1)apksigner
  [[ -x $apksigner ]] || { echo "android: no apksigner under $sdk/build-tools" >&2; exit 1; }
  if ! command -v jarsigner >/dev/null; then
    local java
    java=$(flutter doctor -v 2>/dev/null | sed -n 's/.*Java binary at: //p' | head -1)
    [[ -n $java ]] || { echo "android: no JDK found" >&2; exit 1; }
    export JAVA_HOME=${java%/bin/java}
    export PATH="$JAVA_HOME/bin:$PATH"
  fi
}

# Signs, in place, each APK and bundle in [dir].
sign_android_dir() {
  local dir=$1 apk aab
  read_keystore
  android_tools
  for apk in "$dir"/*.apk; do
    [[ -f $apk ]] || continue
    # Alignment kept as Gradle left it: native libraries sit on 16 KB pages,
    # which Android 15 devices need to map them.
    "$apksigner" sign --ks "$keystore" --ks-key-alias "$key_alias" \
      --ks-pass env:RIFT_STORE_PASS --key-pass env:RIFT_KEY_PASS \
      --alignment-preserved --out "$work/signed.apk" "$apk"
    mv -f "$work/signed.apk" "$apk"
    rm -f "$apk.idsig"
    "$apksigner" verify --print-certs "$apk" |
      sed -n "s|.*certificate SHA-256 digest: |  ${apk##*/} signed by |p"
  done
  for aab in "$dir"/*.aab; do
    [[ -f $aab ]] || continue
    # A bundle is signed as a JAR. The debug key's signature goes first, or
    # jarsigner adds a second signer, which Play refuses.
    unzip -Z1 "$aab" | { grep -E '^META-INF/[^/]+\.(SF|RSA|EC|DSA)$|^META-INF/MANIFEST\.MF$' || true; } |
      xargs -r zip -qd "$aab"
    jarsigner -keystore "$keystore" -storepass:env RIFT_STORE_PASS \
      -keypass:env RIFT_KEY_PASS "$aab" "$key_alias" >/dev/null
    jarsigner -verify "$aab" | grep -q 'jar verified' ||
      { echo "android: ${aab##*/}'s signature does not verify" >&2; exit 1; }
    echo "  ${aab##*/} signed"
  done
  unset RIFT_STORE_PASS RIFT_KEY_PASS
}

sign_android() {
  local tag=$1 version=${1#v}
  sign_android_dir "$work/android"
  gh release upload "$tag" -R "$repo" --clobber "$work"/android/*.apk
  echo "android: APKs uploaded"
  mkdir -p build/release
  cp -f "$work/android/rift-$version-android.aab" build/release/
  echo "android: bundle for Google Play in build/release/rift-$version-android.aab"
  [[ -n $play_notes ]] || return 0
  scripts/play_upload.sh "build/release/rift-$version-android.aab" "$play_notes" ||
    echo "play: not uploaded; the bundle waits in build/release for a manual upload"
}

show_feed() {
  python3 -c '
import json, sys
for a in json.load(open(sys.argv[1]))["Assets"]:
    print("  %s\t%s\t%s\t%s bytes" % tuple(a.get(k) for k in ("Type", "Version", "FileName", "Size")))
' "$1"
}

# Posts a release's notes to each webhook in the keyring: `rift`, `discord`, or
# both when `where` is left out.
announce() {
  local tag=$1 where=${2:-all}
  gh release view "$tag" -R "$repo" --json name,isPrerelease,body,url,assets >"$work/release.json"
  [[ $where == discord ]] || announce_rift
  [[ $where == rift ]] || announce_discord
}

# Hands curl the webhook URL on stdin, not its command line, where ps shows it.
post_to() {
  local url=$1 body=$2 reply=$3
  printf 'url = "%s"\n' "$url" | curl -sS -K - -o "$reply" -w '%{http_code}' \
    -H 'Content-Type: application/json' --data-binary "@$body"
}

# The notes as plain text, since a chat message draws no markdown, then the
# Windows installer, which most people want, and the release's page.
announce_rift() {
  local url
  url=$(secret-tool lookup service rift-release-webhook || true)
  if [[ -z $url ]]; then
    echo "announce: no rift-release-webhook in the keyring, nothing posted"
    return
  fi
  python3 -c '
import json, re, sys
r = json.load(open(sys.argv[1]))
kind = "beta" if r["isPrerelease"] else "release"
notes = re.sub(r"\*\*|`", "", r["body"]).strip()
links = "".join("Windows installer: %s\n" % a["url"] for a in r["assets"]
                if a["name"].endswith("-setup.exe"))
links += "".join("Android APK: %s\n" % a["url"] for a in r["assets"]
                 if a["name"].endswith("-android.apk"))
links += "Release page: %s" % r["url"]
text = "%s is out (%s)\n\n%s\n\n%s" % (r["name"], kind, notes, links)
if len(text) > 16000:
    text = "%s is out (%s)\n\n%s" % (r["name"], kind, links)
json.dump({"text": text}, open(sys.argv[2], "w"))
' "$work/release.json" "$work/announce.json"
  post_to "$url" "$work/announce.json" "$work/reply.json" >/dev/null ||
    { echo "announce: could not reach the webhook"; return; }
  if python3 -c 'import json, sys; sys.exit(0 if json.load(open(sys.argv[1])).get("success") else 1)' \
    "$work/reply.json" 2>/dev/null; then
    echo "announce: posted"
  else
    echo "announce: the webhook refused it: $(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("error"))' "$work/reply.json" 2>/dev/null)"
  fi
}

# Discord draws markdown, so the notes keep their bold and code. A message holds
# 2000 characters; longer notes give way to the links alone. Nobody is pinged,
# and the links draw no previews.
announce_discord() {
  local url status
  url=$(secret-tool lookup service rift-discord-webhook || true)
  if [[ -z $url ]]; then
    echo "discord: no rift-discord-webhook in the keyring, nothing posted"
    return
  fi
  python3 -c '
import json, sys
r = json.load(open(sys.argv[1]))
kind = "beta" if r["isPrerelease"] else "release"
links = "".join("Windows installer: %s\n" % a["url"] for a in r["assets"]
                if a["name"].endswith("-setup.exe"))
links += "".join("Android APK: %s\n" % a["url"] for a in r["assets"]
                 if a["name"].endswith("-android.apk"))
links += "Release page: %s" % r["url"]
head = "## %s is out (%s)" % (r["name"], kind)
text = "%s\n\n%s\n\n%s" % (head, r["body"].strip(), links)
if len(text) > 2000:
    text = "%s\n\n%s" % (head, links)
json.dump({"content": text, "allowed_mentions": {"parse": []}, "flags": 4},
          open(sys.argv[2], "w"))
' "$work/release.json" "$work/discord.json"
  # ?wait=true makes Discord answer with the message, or with why not.
  status=$(post_to "$url?wait=true" "$work/discord.json" "$work/discord-reply.json") ||
    { echo "discord: could not reach the webhook"; return; }
  if [[ $status == 200 ]]; then
    echo "discord: posted"
  else
    echo "discord: the webhook refused it ($status): $(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("message"))' "$work/discord-reply.json" 2>/dev/null)"
  fi
}

if [[ ${1:-} == --announce ]]; then
  announce "${2:?usage: scripts/sign_release.sh --announce <tag> [rift|discord]}" "${3:-}"
  exit 0
fi

if [[ ${1:-} == --android ]]; then
  sign_android_dir "${2:?usage: scripts/sign_release.sh --android DIR}"
  exit 0
fi

if [[ ${1:-} == --dir ]]; then
  dir=${2:?usage: scripts/sign_release.sh --dir DIR}
  for channel in "${channels[@]}"; do
    feed="$dir/releases.$channel.json"
    [[ -f $feed ]] || continue
    echo "$channel:"
    show_feed "$feed"
    sign_feed "$channel" "$feed"
    echo "  signed: $feed.sig"
  done
  exit 0
fi

tag=${1:?usage: scripts/sign_release.sh <tag> [--play-notes FILE], e.g. v1.5.0}
play_notes=
if [[ ${2:-} == --play-notes ]]; then
  play_notes=${3:?usage: scripts/sign_release.sh <tag> --play-notes FILE}
  # Checked before anything is signed, so a typo does not leave Play behind.
  [[ -f $play_notes ]] || { echo "No such notes file: $play_notes" >&2; exit 1; }
  (( $(python3 -c 'import sys; print(len(open(sys.argv[1]).read().strip()))' "$play_notes") <= 500 )) ||
    { echo "$play_notes is over Play's 500 characters" >&2; exit 1; }
fi
gh release view "$tag" -R "$repo" --json name,isPrerelease \
  --jq '"\(.name)\(if .isPrerelease then " (pre-release)" else "" end)"'
for channel in "${channels[@]}"; do
  gh release download "$tag" -R "$repo" -p "releases.$channel.json" -D "$work"
  echo "$channel:"
  show_feed "$work/releases.$channel.json"
done
android=false
if fetch_android "$tag"; then
  android=true
  echo "android:"
  for f in "$work"/android/*; do printf '  %s\t%s bytes\n' "${f##*/}" "$(stat -c %s "$f")"; done
else
  echo "android: no build kept with the release's run, skipped"
fi
if [[ -n $play_notes ]]; then echo "play: the bundle goes to Google Play"; else echo "play: no --play-notes, the bundle is left for a manual upload"; fi
read -rp "Sign these? [y/N] " answer
[[ $answer == [yY] ]] || exit 1
for channel in "${channels[@]}"; do
  sign_feed "$channel" "$work/releases.$channel.json"
  gh release upload "$tag" -R "$repo" --clobber "$work/releases.$channel.json.sig"
  echo "$channel: signed and uploaded"
done
if $android; then sign_android "$tag"; fi
announce "$tag"
