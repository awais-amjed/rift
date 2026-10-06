#!/usr/bin/env bash
# Packs a built Rift with Velopack: the installer (Windows) or AppImage
# (Linux), the full update package, a delta from the release before when
# there is one, and the feed installed copies read. Everything lands in
# build/release, named for the release.
#
#   scripts/vpk_pack.sh win   build/windows/x64/runner/Release
#   scripts/vpk_pack.sh linux build/linux/x64/release/bundle
#
# VERSION is the release's version (default: pubspec.yaml's). The notes are
# the tag's message on a tag build, and NOTES (a file) otherwise. With
# GH_TOKEN set, the newest release of the same kind (a pre-release for a
# pre-release) is fetched first, so the delta can be made against it.
#
# Needs vpk, the version in .github/workflows/release.yml, on the PATH or in
# ~/.dotnet/tools.
set -euo pipefail
cd "$(dirname "$0")/.."

channel=${1:?usage: scripts/vpk_pack.sh win|linux <built app folder>}
from=${2:?usage: scripts/vpk_pack.sh win|linux <built app folder>}
version=${VERSION:-$(sed -n 's/^version: //p' pubspec.yaml)}
version=${version%%+*}
repo_url=${REPO_URL:-https://github.com/awais-amjed/rift}
export PATH="$PATH:$HOME/.dotnet/tools"
# A .NET installed into the home folder (dotnet-install) is found through this.
[[ -z ${DOTNET_ROOT:-} && -d $HOME/.dotnet ]] && export DOTNET_ROOT=$HOME/.dotnet
export DOTNET_CLI_TELEMETRY_OPTOUT=1

# Velopack's own folder under the release one: the delta's base is fetched
# into it, and must not be published again.
work=build/velopack/$channel
rm -rf "$work"
mkdir -p "$work" build/release

notes=$work/notes.md
if [[ ${GITHUB_REF_TYPE:-} == tag ]]; then
  # A checkout holds the tag without its message.
  git fetch -q --force origin "refs/tags/$GITHUB_REF_NAME:refs/tags/$GITHUB_REF_NAME"
  git tag -l --format='%(contents)' "$GITHUB_REF_NAME" >"$notes"
elif [[ -n ${NOTES:-} ]]; then
  cp "$NOTES" "$notes"
else
  : >"$notes"
fi

if [[ -n ${GH_TOKEN:-} ]]; then
  pre=()
  [[ $version == *-* ]] && pre=(--pre)
  # The first release packed this way has nothing before it to delta from.
  vpk download github --repoUrl "$repo_url" --channel "$channel" \
    --token "$GH_TOKEN" "${pre[@]}" -o "$work" ||
    echo "No earlier release for $channel; full package only."
fi

common=(-u CodingFries.Rift -v "$version" -p "$from" --channel "$channel"
  --packTitle Rift --packAuthors "Coding Fries" --releaseNotes "$notes" -o "$work")
case $channel in
  win)
    # The hooks are answered by the runner, not a VelopackApp in rift.exe
    # (windows/runner/velopack_hooks.cpp), which vpk cannot see. The AUMID is
    # the one notifications are posted under (ToastIdentity).
    vpk "[win]" pack "${common[@]}" -e rift.exe \
      -i windows/runner/resources/app_icon.ico \
      --aumid CodingFries.Rift --skipVeloAppCheck --noPortable
    mv "$work/CodingFries.Rift-win-Setup.exe" \
      "build/release/Rift-$version-windows-x64-setup.exe"
    ;;
  linux)
    vpk "[linux]" pack "${common[@]}" -e rift -i linux/packaging/rift.png \
      --categories "Network;InstantMessaging;Chat;"
    mv "$work/CodingFries.Rift.AppImage" "build/release/rift-$version-linux-x64.AppImage"
    ;;
  *)
    echo "Unknown channel: $channel" >&2
    exit 1
    ;;
esac

cp "$work/releases.$channel.json" build/release/
cp "$work"/CodingFries.Rift-"$version"-*.nupkg build/release/
ls -l build/release
