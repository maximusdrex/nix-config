#!/usr/bin/env bash
set -euo pipefail

MACHINE="${1:-}"
DEST="${2:-/etc/secret-vars/key.txt}"

if [[ -z "$MACHINE" ]]; then
  echo "Usage: $0 <machine> [destination]"
  echo "Example: $0 max-g14-nix"
  exit 1
fi

for cmd in age age-keygen mktemp sudo install; do
  command -v "$cmd" >/dev/null || {
    echo "ERROR: missing command: $cmd"
    echo "Hint: run inside 'nix develop .#bootstrap' if needed."
    exit 1
  }
done

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEY_DIR="$ROOT_DIR/secrets/age-keys/machines/$MACHINE"
ENCRYPTED_KEY_FILE="$KEY_DIR/key.age"
PUBKEY_FILE="$KEY_DIR/pub"

if [[ ! -f "$ENCRYPTED_KEY_FILE" ]]; then
  echo "ERROR: encrypted machine key not found: $ENCRYPTED_KEY_FILE"
  exit 1
fi

if [[ ! -f "$PUBKEY_FILE" ]]; then
  echo "ERROR: machine public key not found: $PUBKEY_FILE"
  exit 1
fi

if [[ -z "${AGE_KEYFILE:-}" ]]; then
  default_identity="$ROOT_DIR/sops/users/max/fido-identities.txt"
  if [[ -f "$default_identity" ]]; then
    export AGE_KEYFILE="$default_identity"
  else
    echo "ERROR: AGE_KEYFILE is not set and no default operator identity exists at $default_identity"
    exit 1
  fi
fi

TMP_KEY="$(mktemp)"
trap 'rm -f "$TMP_KEY"' EXIT

age --decrypt -i "$AGE_KEYFILE" "$ENCRYPTED_KEY_FILE" > "$TMP_KEY"
chmod 600 "$TMP_KEY"

expected_pub="$(tr -d '\n' < "$PUBKEY_FILE")"
actual_pub="$(age-keygen -y "$TMP_KEY" | tr -d '\n')"

if [[ "$expected_pub" != "$actual_pub" ]]; then
  echo "ERROR: decrypted machine key does not match repo public key"
  echo "repo : $expected_pub"
  echo "file : $actual_pub"
  exit 1
fi

sudo install -Dm600 "$TMP_KEY" "$DEST"

echo "Restored runtime machine AGE key for $MACHINE"
echo "  destination: $DEST"
echo "  public key : $actual_pub"
