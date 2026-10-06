#!/usr/bin/env bash
# Signs a release's update feeds, which is what lets installed copies of Rift
# update to it.
#
#   scripts/sign_release.sh v1.5.0         # the GitHub release of that tag
#   scripts/sign_release.sh --dir DIR      # the feeds in a folder (testing)
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

show_feed() {
  python3 -c '
import json, sys
for a in json.load(open(sys.argv[1]))["Assets"]:
    print("  %s\t%s\t%s\t%s bytes" % tuple(a.get(k) for k in ("Type", "Version", "FileName", "Size")))
' "$1"
}

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

tag=${1:?usage: scripts/sign_release.sh <tag>, e.g. v1.5.0}
gh release view "$tag" -R "$repo" --json name,isPrerelease \
  --jq '"\(.name)\(if .isPrerelease then " (pre-release)" else "" end)"'
for channel in "${channels[@]}"; do
  gh release download "$tag" -R "$repo" -p "releases.$channel.json" -D "$work"
  echo "$channel:"
  show_feed "$work/releases.$channel.json"
done
read -rp "Sign these? [y/N] " answer
[[ $answer == [yY] ]] || exit 1
for channel in "${channels[@]}"; do
  sign_feed "$channel" "$work/releases.$channel.json"
  gh release upload "$tag" -R "$repo" --clobber "$work/releases.$channel.json.sig"
  echo "$channel: signed and uploaded"
done
