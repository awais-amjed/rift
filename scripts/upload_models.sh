#!/usr/bin/env bash
# Prints the catalog entry for each downloaded model (lib/data/model_catalog.dart),
# and with --upload, adds the files the release does not have yet to the
# GitHub release `models` they are downloaded from.
#
#   scripts/upload_models.sh            # print the entries, change nothing
#   scripts/upload_models.sh --upload   # and upload what is missing (gh, signed in)
#
# The release only ever gains files: an older Rift keeps downloading the
# version it pinned. So a changed model goes up under a new published name
# (image_safety.v2.tflite), and a name already in the release is never
# replaced — gh refuses to, without --clobber, which this never passes.
#
# The release is a pre-release that is never "Latest", and has no update feed,
# so the updater passes over it (rust/src/updater/source.rs).
set -euo pipefail
cd "$(dirname "$0")/.."

repo=${REPO:-awais-amjed/rift}
tag=models

# published name → file in this repository, or ceva:<path> for a file in
# Ceva's DPDFNet download at the commit native/dpdfnet/build.sh pins
models=(
  "image_safety.v1.tflite=assets/models/image_safety.tflite"
  "dpdfnet8.ceva.v1.f32=ceva:models/dpdfnet8_48khz_hr/weights.f32"
  "dpdfnet2.ceva.v1.f32=ceva:models/dpdfnet2_48khz_hr/weights.f32"
)

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

# Ceva's download, fetched once and checked against build.sh's hash, as the
# build checks it; RIFT_DPDFNET_TARBALL names one already here.
ceva=
ceva_file() {
  if [[ -z $ceva ]]; then
    local commit sha256 tarball
    commit=$(sed -n 's/^commit=//p' native/dpdfnet/build.sh)
    sha256=$(sed -n 's/^sha256=//p' native/dpdfnet/build.sh)
    tarball=${RIFT_DPDFNET_TARBALL:-$stage/ceva.tar.gz}
    if [[ ! -f $tarball ]]; then
      curl -fsSL "https://github.com/ceva-ip/DPDFNet/archive/$commit.tar.gz" -o "$tarball"
    fi
    echo "$sha256  $tarball" | sha256sum -c --quiet
    ceva=$stage/ceva
    mkdir -p "$ceva"
    tar -C "$ceva" --strip-components=2 -xzf "$tarball" "DPDFNet-$commit/optimized_inference"
    (cd "$ceva" && sha256sum -c --quiet models/SHA256SUMS)
  fi
  echo "$ceva/$1"
}

for entry in "${models[@]}"; do
  published=${entry%%=*}
  source=${entry#*=}
  if [[ $source == ceva:* ]]; then
    ceva_file "${source#ceva:}" >/dev/null
    source=$ceva/${source#ceva:}
  fi
  [[ -f $source ]] || { echo "missing: $source" >&2; exit 1; }
  size=$(stat -c %s "$source")
  hash=$(sha256sum "$source" | cut -d' ' -f1)
  printf "%s\n  published: '%s',\n  size: %s,\n  sha256: '%s',\n\n" \
    "$source" "$published" "$size" "$hash"
  cp "$source" "$stage/$published"
done

[[ ${1:-} == --upload ]] || exit 0

if ! gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  gh release create "$tag" --repo "$repo" --prerelease --latest=false \
    --title "Models" \
    --notes "Files Rift downloads instead of shipping. Each is pinned by its SHA-256 in the app (lib/data/model_catalog.dart); files are only ever added here, never replaced."
fi

have=$(gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name')
for file in "$stage"/*; do
  name=$(basename "$file")
  if grep -qxF "$name" <<<"$have"; then
    echo "already there: $name"
  else
    gh release upload "$tag" "$file" --repo "$repo"
    echo "uploaded: $name"
  fi
done
