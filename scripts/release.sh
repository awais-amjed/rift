#!/usr/bin/env bash
# Makes a release: sets pubspec.yaml's version, commits it and tags it.
#
#   scripts/release.sh 1.0.3                 # a release
#   scripts/release.sh 1.1.0-beta.1          # a pre-release: anything with a `-`
#   scripts/release.sh 1.0.3 notes.md        # release notes from a file
#
# The tag's message is the release's notes, so without a notes file git opens
# an editor for them. The build number after `+` goes up by one every time,
# betas included: Android refuses an update whose number is not higher.
#
# Nothing is pushed. When the commit and the tag look right:
#
#   git push origin HEAD v1.0.3
#
# The push mirror carries the tag to GitHub, where
# .github/workflows/release.yml builds the release from it.
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?usage: scripts/release.sh <version> [notes-file], e.g. 1.0.3 or 1.1.0-beta.1}
notes=${2:-}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] ||
  { echo "Not a version: $version (expected 1.0.3 or 1.1.0-beta.1)" >&2; exit 1; }
[[ -z $notes || -f $notes ]] || { echo "No such notes file: $notes" >&2; exit 1; }
git diff --quiet && git diff --cached --quiet ||
  { echo "Commit or stash your changes first." >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/v$version" >/dev/null ||
  { echo "v$version already exists." >&2; exit 1; }

current=$(sed -n 's/^version: //p' pubspec.yaml)
[[ ${current%%+*} != "$version" ]] || { echo "pubspec.yaml is already $current." >&2; exit 1; }
build=$(( ${current##*+} + 1 ))

sed -i "s/^version: .*/version: $version+$build/" pubspec.yaml
git commit -q -m "Release $version" -- pubspec.yaml
# An empty message (the editor closed without notes) refuses the tag; take the
# commit back with it, so a second try starts from where this one did.
if ! git tag -a "v$version" ${notes:+-F "$notes"}; then
  git reset -q --hard HEAD~1
  echo "No tag made; pubspec.yaml is back to $current." >&2
  exit 1
fi
echo "Tagged v$version ($version+$build). Push with: git push origin HEAD v$version"
