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

# ONNX Runtime, Microsoft's own CPU build, for DPDFNet where Ceva's runtime
# cannot run (rust/src/dpdfnet/onnx.rs); its licences ship in
# assets/licenses/onnxruntime.txt. Each archive is checked against the hash
# of Microsoft's release.
ort_version=1.28.2
ort_release=https://github.com/microsoft/onnxruntime/releases/download/v$ort_version
ort_linux=onnxruntime-linux-x64-$ort_version.tgz
ort_linux_sha256=d7209b8751b27b862b0c76332c2e20e203396edb5dab700ecf4bb485cf147415
ort_windows=onnxruntime-win-x64-$ort_version.zip
ort_windows_sha256=c4eedd29489d5feca21866d054638416f3655bf6b18851b3b6b85c8313e95c35

# published name → file in this repository, ceva:<path> for a file in
# Ceva's DPDFNet download at the commit native/dpdfnet/build.sh pins, or
# ort:<archive>:<path> for one in an ONNX Runtime archive
models=(
  "image_safety.v1.tflite=assets/models/image_safety.tflite"
  "dpdfnet8.ceva.v1.f32=ceva:models/dpdfnet8_48khz_hr/weights.f32"
  "dpdfnet2.ceva.v1.f32=ceva:models/dpdfnet2_48khz_hr/weights.f32"
  "dpdfnet8_48khz_hr.v1.onnx=rust/models/dpdfnet8_48khz_hr.onnx"
  "dpdfnet2_48khz_hr.v1.onnx=rust/models/dpdfnet2_48khz_hr.onnx"
  "libonnxruntime.linux-x64.$ort_version.so=ort:$ort_linux:lib/libonnxruntime.so.$ort_version"
  "onnxruntime.win-x64.$ort_version.dll=ort:$ort_windows:lib/onnxruntime.dll"
)

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
# what goes up, apart from Ceva's download, which is unpacked beside it
upload=$stage/upload
mkdir "$upload"

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

# One file from an ONNX Runtime archive, which is fetched once and checked.
ort_file() {
  local archive=$1 member=$2 sha256 dir=$stage/ort
  case $archive in
    "$ort_linux") sha256=$ort_linux_sha256 ;;
    "$ort_windows") sha256=$ort_windows_sha256 ;;
  esac
  mkdir -p "$dir"
  if [[ ! -f $dir/$archive ]]; then
    curl -fsSL "$ort_release/$archive" -o "$dir/$archive"
    echo "$sha256  $dir/$archive" | sha256sum -c --quiet
  fi
  local out=$dir/${archive%.*}/$member
  if [[ ! -f $out ]]; then
    mkdir -p "$(dirname "$out")"
    # Both archives hold one top folder, named after the archive.
    case $archive in
      *.tgz) tar -xzOf "$dir/$archive" "${archive%.tgz}/$member" >"$out" ;;
      *.zip) unzip -p "$dir/$archive" "${archive%.zip}/$member" >"$out" ;;
    esac
  fi
  echo "$out"
}

for entry in "${models[@]}"; do
  published=${entry%%=*}
  source=${entry#*=}
  if [[ $source == ceva:* ]]; then
    ceva_file "${source#ceva:}" >/dev/null
    source=$ceva/${source#ceva:}
  elif [[ $source == ort:* ]]; then
    source=${source#ort:}
    source=$(ort_file "${source%%:*}" "${source#*:}")
  fi
  [[ -f $source ]] || { echo "missing: $source" >&2; exit 1; }
  size=$(stat -c %s "$source")
  hash=$(sha256sum "$source" | cut -d' ' -f1)
  printf "%s\n  published: '%s',\n  size: %s,\n  sha256: '%s',\n\n" \
    "$source" "$published" "$size" "$hash"
  cp "$source" "$upload/$published"
done

[[ ${1:-} == --upload ]] || exit 0

if ! gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  gh release create "$tag" --repo "$repo" --prerelease --latest=false \
    --title "Models" \
    --notes "Files Rift downloads instead of shipping. Each is pinned by its SHA-256 in the app (lib/data/model_catalog.dart); files are only ever added here, never replaced."
fi

have=$(gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name')
for file in "$upload"/*; do
  name=$(basename "$file")
  if grep -qxF "$name" <<<"$have"; then
    echo "already there: $name"
  else
    gh release upload "$tag" "$file" --repo "$repo"
    echo "uploaded: $name"
  fi
done
