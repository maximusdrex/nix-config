#!/usr/bin/env bash
set -euo pipefail

MACHINE="${1:-}"
KEY_SOURCE="${2:-}"

if [[ -z "$MACHINE" ]]; then
  echo "Usage: $0 <machine> [key-file]"
  echo "Examples:"
  echo "  $0 max-g14-nix"
  echo "  $0 max-xps-modal /path/to/key.txt"
  exit 1
fi

for cmd in age age-keygen mktemp nix ssh sudo; do
  command -v "$cmd" >/dev/null || {
    echo "ERROR: missing command: $cmd"
    echo "Hint: run inside 'nix develop .#bootstrap' if needed."
    exit 1
  }
done

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TMPDIR="$(mktemp -d /tmp/enroll-machine-age-key.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

TMP_KEY="$TMPDIR/key.txt"
TARGET_HOST="$(
  nix eval --json ".#clan.inventory.machines.${MACHINE}.deploy.targetHost" | tr -d '"' | sed 's/^null$//'
)"

if [[ -n "$KEY_SOURCE" ]]; then
  if [[ ! -f "$KEY_SOURCE" ]]; then
    echo "ERROR: key file not found: $KEY_SOURCE"
    exit 1
  fi
  cp "$KEY_SOURCE" "$TMP_KEY"
elif [[ -n "$TARGET_HOST" ]]; then
  ssh "$TARGET_HOST" 'sudo cat /etc/secret-vars/key.txt' > "$TMP_KEY"
else
  sudo cat /etc/secret-vars/key.txt > "$TMP_KEY"
fi

chmod 600 "$TMP_KEY"

PUBKEY="$(age-keygen -y "$TMP_KEY" | tr -d '\n')"
if [[ -z "$PUBKEY" ]]; then
  echo "ERROR: failed to derive machine public key"
  exit 1
fi

KEY_DIR="$ROOT_DIR/secrets/age-keys/machines/$MACHINE"
PUBKEY_FILE="$KEY_DIR/pub"
ENCRYPTED_KEY_FILE="$KEY_DIR/key.age"
RECIPIENTS_FILE="$KEY_DIR/key.age.recipients"

install -d "$KEY_DIR"
printf '%s\n' "$PUBKEY" > "$PUBKEY_FILE"

mapfile -t recipients < <(nix eval --raw --file "$ROOT_DIR/scripts/print-operator-age-recipients.nix")
if [[ "${#recipients[@]}" -eq 0 ]]; then
  echo "ERROR: no operator recipients found under sops/users"
  exit 1
fi

age_args=()
for recipient in "${recipients[@]}"; do
  [[ -n "$recipient" ]] || continue
  age_args+=("-r" "$recipient")
done

age --armor "${age_args[@]}" -o "$ENCRYPTED_KEY_FILE" "$TMP_KEY"
printf '%s\n' "${recipients[@]}" | sed '/^$/d' | sort -u > "$RECIPIENTS_FILE"

echo "Synced machine runtime AGE key for $MACHINE"
echo "  public key: $PUBKEY"
echo "  machine key dir: $KEY_DIR"
echo "  encrypted private key: $ENCRYPTED_KEY_FILE"
