#!/usr/bin/env bash
# Puts a signed app bundle on Google Play, through the Play Developer API.
#
#   scripts/play_upload.sh check                 # sign in and show the tracks; changes nothing
#   scripts/play_upload.sh BUNDLE NOTES          # upload, with what's new from a file
#
# A beta (a version with a `-`) goes to open testing (the API's `beta` track)
# and rolls out to its testers once Google has reviewed it. A release goes to
# production as a draft: it waits in Play Console for somebody to look at it
# and send it for review, since that one reaches everybody.
#
# NOTES is plain text, what Play shows under "What's new", in English and at
# most 500 characters. It is written for Android: the GitHub notes speak of
# installers and other systems.
#
# It signs in as a Google service account whose JSON key lives in the
# keyring (`secret-tool store --label='Rift Play upload' service
# rift-play-upload < key.json`), invited in Play Console's Users and
# permissions with leave to release Rift. scripts/sign_release.sh runs it
# when given --play-notes.
set -euo pipefail
cd "$(dirname "$0")/.."

package=com.codingfries.rift
api=https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$package
upload_api=https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$package

work=$(mktemp -d)
edit=
trap 'rm -rf "$work"' EXIT

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# An access token for the service account: a JWT it signs with its own key,
# traded at Google's token endpoint. The key is on disk only while signing.
sign_in() {
  local account header claims signature
  account=$(secret-tool lookup service rift-play-upload || true)
  [[ -n $account ]] ||
    { echo "play: no rift-play-upload in the keyring" >&2; exit 1; }
  printf '%s' "$account" | python3 -c '
import json, sys, time
a = json.load(sys.stdin)
open(sys.argv[1], "w").write(a["private_key"])
now = int(time.time())
json.dump({"iss": a["client_email"], "aud": a["token_uri"], "iat": now, "exp": now + 3600,
           "scope": "https://www.googleapis.com/auth/androidpublisher"},
          open(sys.argv[2], "w"))
open(sys.argv[3], "w").write(a["token_uri"])
' "$work/key.pem" "$work/claims.json" "$work/token_uri"
  unset account
  header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
  claims=$(b64url <"$work/claims.json")
  signature=$(printf '%s.%s' "$header" "$claims" |
    openssl dgst -sha256 -sign "$work/key.pem" -binary | b64url)
  rm "$work/key.pem"
  # The assertion goes in a file, not on curl's command line, where ps shows it.
  printf 'grant_type=urn%%3Aietf%%3Aparams%%3Aoauth%%3Agrant-type%%3Ajwt-bearer&assertion=%s.%s.%s' \
    "$header" "$claims" "$signature" >"$work/token_request"
  curl -sS -o "$work/token.json" --data-binary "@$work/token_request" \
    -H 'Content-Type: application/x-www-form-urlencoded' "$(cat "$work/token_uri")"
  rm "$work/token_request"
  token=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("access_token", ""))' \
    "$work/token.json")
  [[ -n $token ]] || {
    echo "play: Google refused the sign-in: $(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("error_description"))' "$work/token.json")" >&2
    exit 1
  }
  rm "$work/token.json"
}

# One API call. The token goes to curl on stdin, not its command line. Writes
# the reply to $work/reply.json and fails with Google's reason on an error.
call() {
  local method=$1 url=$2 status
  shift 2
  status=$(printf 'header = "Authorization: Bearer %s"\n' "$token" |
    curl -sS -K - -X "$method" -o "$work/reply.json" -w '%{http_code}' "$@" "$url")
  [[ $status == 2* ]] && return 0
  reason=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["error"]["message"])' \
    "$work/reply.json" 2>/dev/null || echo "HTTP $status")
  return 1
}

field() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$work/reply.json" "$1"; }

# Everything goes through an edit, which nobody sees until it is committed. One
# left open after a failure is thrown away, so the next run starts clean.
open_edit() {
  call POST "$api/edits" || { echo "play: could not open an edit: $reason" >&2; exit 1; }
  edit=$(field id)
  trap 'discard_edit; rm -rf "$work"' EXIT
}

discard_edit() {
  [[ -n $edit ]] || return 0
  call DELETE "$api/edits/$edit" || true
  edit=
}

fail() { echo "play: $1: $reason" >&2; exit 1; }

if [[ ${1:-} == check ]]; then
  sign_in
  open_edit
  call GET "$api/edits/$edit/tracks" || fail "could not read the tracks"
  python3 -c '
import json, sys
for t in json.load(open(sys.argv[1])).get("tracks", []):
    for r in t.get("releases", []):
        print("  %s\t%s\t%s\t%s" % (t["track"], r.get("name", ""), r.get("status", ""),
                                    ",".join(r.get("versionCodes", []))))
' "$work/reply.json"
  echo "play: signed in, nothing changed"
  exit 0
fi

bundle=${1:?usage: scripts/play_upload.sh check | BUNDLE NOTES}
notes=${2:?usage: scripts/play_upload.sh BUNDLE NOTES}
[[ -f $bundle ]] || { echo "play: no such bundle: $bundle" >&2; exit 1; }
[[ -f $notes ]] || { echo "play: no such notes file: $notes" >&2; exit 1; }
length=$(python3 -c 'import sys; print(len(open(sys.argv[1]).read().strip()))' "$notes")
(( length <= 500 )) ||
  { echo "play: the notes are $length characters, and Play takes 500" >&2; exit 1; }
version=$(basename "$bundle")
version=${version#rift-}
version=${version%-android.aab}
if [[ $version == *-* ]]; then track=beta status=completed; else track=production status=draft; fi

sign_in
open_edit
echo "play: uploading ${bundle##*/}"
call POST "$upload_api/edits/$edit/bundles?uploadType=media" \
  -H 'Content-Type: application/octet-stream' --data-binary "@$bundle" ||
  fail "the upload was refused"
code=$(field versionCode)
# Named the way Play Console names a release it is handed by hand.
python3 -c '
import json, sys
json.dump({"track": sys.argv[1], "releases": [{
    "name": "%s (%s)" % (sys.argv[3], sys.argv[2]), "versionCodes": [sys.argv[3]], "status": sys.argv[4],
    "releaseNotes": [{"language": "en-US", "text": open(sys.argv[5]).read().strip()}]}]},
    open(sys.argv[6], "w"))
' "$track" "$version" "$code" "$status" "$notes" "$work/track.json"
call PUT "$api/edits/$edit/tracks/$track" \
  -H 'Content-Type: application/json' --data-binary "@$work/track.json" ||
  fail "could not put build $code on $track"
# An app whose last change Google has not yet passed cannot send another for
# review from here; it is then committed as a change waiting in Play Console.
if call POST "$api/edits/$edit:commit"; then
  sent=true
elif [[ $reason == *changesNotSentForReview* ]] &&
  call POST "$api/edits/$edit:commit?changesNotSentForReview=true"; then
  sent=false
else
  fail "could not commit build $code"
fi
edit=
if [[ $status == draft ]]; then
  echo "play: build $code is a draft on production; send it for review in Play Console"
elif $sent; then
  echo "play: build $code sent for review on open testing"
else
  echo "play: build $code is on open testing; send it for review in Play Console (Publishing overview)"
fi
