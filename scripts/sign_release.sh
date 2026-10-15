#!/usr/bin/env bash
# Signs a release's update feeds, which is what lets installed copies of Rift
# update to it.
#
#   scripts/sign_release.sh v1.5.0         # the GitHub release of that tag
#   scripts/sign_release.sh --dir DIR      # the feeds in a folder (testing)
#   scripts/sign_release.sh --announce v1.5.0   # only post the announcement
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
# rift-release-webhook`), and without one nothing is posted.
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

# The notes as plain text, since a chat message draws no markdown, then the
# Windows installer, which most people want, and the release's page.
announce() {
  local tag=$1 url
  url=$(secret-tool lookup service rift-release-webhook || true)
  if [[ -z $url ]]; then
    echo "announce: no rift-release-webhook in the keyring, nothing posted"
    return
  fi
  gh release view "$tag" -R "$repo" --json name,isPrerelease,body,url,assets >"$work/release.json"
  python3 -c '
import json, re, sys
r = json.load(open(sys.argv[1]))
kind = "beta" if r["isPrerelease"] else "release"
notes = re.sub(r"\*\*|`", "", r["body"]).strip()
links = "".join("Windows installer: %s\n" % a["url"] for a in r["assets"]
                if a["name"].endswith("-setup.exe"))
links += "Release page: %s" % r["url"]
text = "%s is out (%s)\n\n%s\n\n%s" % (r["name"], kind, notes, links)
if len(text) > 16000:
    text = "%s is out (%s)\n\n%s" % (r["name"], kind, links)
json.dump({"text": text}, open(sys.argv[2], "w"))
' "$work/release.json" "$work/announce.json"
  # The URL goes to curl on stdin, not its command line, where ps shows it.
  printf 'url = "%s"\n' "$url" | curl -sS -K - -o "$work/reply.json" \
    -H 'Content-Type: application/json' --data-binary "@$work/announce.json" ||
    { echo "announce: could not reach the webhook"; return; }
  if python3 -c 'import json, sys; sys.exit(0 if json.load(open(sys.argv[1])).get("success") else 1)' \
    "$work/reply.json" 2>/dev/null; then
    echo "announce: posted"
  else
    echo "announce: the webhook refused it: $(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("error"))' "$work/reply.json" 2>/dev/null)"
  fi
}

if [[ ${1:-} == --announce ]]; then
  announce "${2:?usage: scripts/sign_release.sh --announce <tag>}"
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
announce "$tag"
