#!/usr/bin/env bash
# Refreshes assets/certificates/mozilla_roots.pem: Mozilla's trusted roots, as
# curl extracts them (https://curl.se/docs/caextract.html), checked against
# the SHA-256 curl publishes beside the file. Run before a release now and
# then; the file's header says which Mozilla data it holds.
#
# Why the app carries them: TrustedRoots (lib/logic/services/trusted_roots.dart).
set -euo pipefail

cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

curl -sSfL -o "$work/cacert.pem" https://curl.se/ca/cacert.pem
curl -sSfL -o "$work/cacert.pem.sha256" https://curl.se/ca/cacert.pem.sha256
(cd "$work" && sha256sum -c cacert.pem.sha256)

count=$(grep -c 'BEGIN CERTIFICATE' "$work/cacert.pem")
if [ "$count" -lt 100 ]; then
  echo "Only $count certificates in the download; not using it." >&2
  exit 1
fi

cp "$work/cacert.pem" assets/certificates/mozilla_roots.pem
grep -m1 'Certificate data from Mozilla' assets/certificates/mozilla_roots.pem
echo "$count roots written to assets/certificates/mozilla_roots.pem"
