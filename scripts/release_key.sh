#!/usr/bin/env bash
# Rift's release key: the Ed25519 key every update feed is signed with.
#
#   scripts/release_key.sh generate        # make it, once, into the keyring
#   scripts/release_key.sh public          # its public half, for RELEASE_KEYS
#   scripts/release_key.sh export FILE     # a passphrase-protected backup
#   scripts/release_key.sh import FILE     # put a backup back in the keyring
#
# The private half lives in the system keyring (secret-tool, service
# "rift-release-key") and nowhere else: not in the repository, not in CI.
# Installed copies of Rift accept an update only when its feed carries a
# signature from a key in RELEASE_KEYS (rust/src/updater/signature.rs), so
# losing this key means no copy can be updated again without a reinstall.
# Keep the export somewhere safe and offline.
#
# RIFT_RELEASE_KEY_FILE names a PEM file to use instead of the keyring.
set -euo pipefail

service=rift-release-key

private_pem() {
  if [[ -n ${RIFT_RELEASE_KEY_FILE:-} ]]; then
    cat "$RIFT_RELEASE_KEY_FILE"
  else
    secret-tool lookup service "$service" ||
      { echo "No release key in the keyring. Run: scripts/release_key.sh generate" >&2; exit 1; }
  fi
}

case ${1:-} in
  generate)
    if secret-tool lookup service "$service" >/dev/null 2>&1; then
      echo "A release key is already in the keyring." >&2
      exit 1
    fi
    openssl genpkey -algorithm ed25519 |
      secret-tool store --label="Rift release key" service "$service"
    echo "Stored. Its public half, for RELEASE_KEYS:"
    "$0" public
    echo "Now back it up: scripts/release_key.sh export <file>"
    ;;
  public)
    # The DER form ends with the 32 raw bytes of the key.
    private_pem | openssl pkey -pubout -outform DER | tail -c 32 | openssl base64 -A
    echo
    ;;
  export)
    out=${2:?usage: scripts/release_key.sh export FILE}
    [[ ! -e $out ]] || { echo "$out already exists." >&2; exit 1; }
    private_pem | openssl pkey -aes256 -out "$out"
    echo "Wrote $out, sealed with the passphrase you typed."
    ;;
  import)
    in=${2:?usage: scripts/release_key.sh import FILE}
    if secret-tool lookup service "$service" >/dev/null 2>&1; then
      echo "A release key is already in the keyring." >&2
      exit 1
    fi
    openssl pkey -in "$in" | secret-tool store --label="Rift release key" service "$service"
    echo "Stored."
    ;;
  *)
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
