#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
  echo "Usage: $0 /dev/sdX"
  exit 1
fi

if [[ ! -b "$DEVICE" ]]; then
  echo "ERROR: $DEVICE is not a block device"
  exit 1
fi

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run as your user (script uses sudo when needed)."
  exit 1
fi

for cmd in nix age tar rsync; do
  command -v "$cmd" >/dev/null || { echo "Missing command: $cmd"; exit 1; }
done

if ! command -v age-plugin-fido2-hmac >/dev/null 2>&1; then
  echo "ERROR: age-plugin-fido2-hmac is required. Run inside nix develop .#bootstrap"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p bootstrap

SOPS_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
if [[ ! -s "$SOPS_KEY_FILE" ]]; then
  echo "ERROR: SOPS age key file not found or empty: $SOPS_KEY_FILE"
  exit 1
fi

echo "==> Insert your FIDO2/U2F security key now."
read -r -p "Press Enter when ready to generate identity... " _

IDENTITY_FILE="bootstrap/fido2-identity.txt"
RECIPIENT_FILE="bootstrap/fido2-recipient.txt"

echo "==> Generating fresh FIDO2 age identity"
age-plugin-fido2-hmac -g > "$IDENTITY_FILE"
chmod 600 "$IDENTITY_FILE"

recipient="$(grep -Eo 'age1[0-9a-z]+' "$IDENTITY_FILE" | head -n1 || true)"
if [[ -z "$recipient" ]]; then
  echo "ERROR: Could not extract recipient from $IDENTITY_FILE"
  exit 1
fi
printf '%s\n' "$recipient" > "$RECIPIENT_FILE"
chmod 600 "$RECIPIENT_FILE"

echo "==> Building encrypted bootstrap payload"
TMPDIR="$(mktemp -d /tmp/bootstrap-payload.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/payload/opt/nix-config" "$TMPDIR/payload/bootstrap-secrets"

rsync -a --delete \
  --exclude '.git' \
  --exclude 'result' \
  --exclude 'bootstrap/payload.age' \
  --exclude 'bootstrap/fido2-identity.txt' \
  --exclude 'bootstrap/fido2-recipient.txt' \
  "$ROOT_DIR/" "$TMPDIR/payload/opt/nix-config/"

cp "$SOPS_KEY_FILE" "$TMPDIR/payload/bootstrap-secrets/sops-age-key.txt"
chmod 600 "$TMPDIR/payload/bootstrap-secrets/sops-age-key.txt"

TAR_PATH="$TMPDIR/payload.tar.gz"
tar -C "$TMPDIR/payload" -czf "$TAR_PATH" .

age -R "$RECIPIENT_FILE" -o bootstrap/payload.age "$TAR_PATH"
chmod 600 bootstrap/payload.age

echo "Wrote bootstrap/payload.age"

FONT_ARCHIVE="${BOOTSTRAP_BERKELEY_MONO_FILE:-$ROOT_DIR/bootstrap/berkeley-mono-1.009.zip}"
if [[ -f "$FONT_ARCHIVE" ]]; then
  echo "==> Including Berkeley Mono archive from: $FONT_ARCHIVE"
  cp "$FONT_ARCHIVE" "$TMPDIR/payload/bootstrap-secrets/berkeley-mono-1.009.zip"
else
  echo "==> Berkeley Mono archive not found (optional): $FONT_ARCHIVE"
fi

echo "==> Building bootstrap installer ISO (local-only builders, including generated payload files)"
NIX_CONFIG=$'builders =\n' nix build "path:$ROOT_DIR#bootstrap-installer-iso" --no-link -o result

RESULT_PATH="$(readlink -f result)"
if [[ -f "$RESULT_PATH" && "$RESULT_PATH" == *.iso ]]; then
  ISO_PATH="$RESULT_PATH"
else
  ISO_PATH="$(find "$RESULT_PATH" -type f -name '*.iso' | head -n1 || true)"
fi

if [[ -z "$ISO_PATH" || ! -f "$ISO_PATH" ]]; then
  echo "ERROR: Could not locate built ISO under $RESULT_PATH"
  exit 1
fi

echo "==> About to erase and write $DEVICE with $ISO_PATH"
read -r -p "Type YES to continue: " confirm
[[ "$confirm" == "YES" ]] || { echo "Aborted"; exit 1; }

sudo dd if="$ISO_PATH" of="$DEVICE" bs=4M conv=fsync status=progress
sync

echo "Done. Boot from $DEVICE, then run: bootstrap-unlock"
