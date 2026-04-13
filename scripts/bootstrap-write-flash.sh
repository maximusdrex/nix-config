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

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p bootstrap

if [[ ! -s "$ROOT_DIR/sops/users/max/fido-identities.txt" ]]; then
  echo "ERROR: missing repo-tracked FIDO identity stub: sops/users/max/fido-identities.txt"
  echo "The installer uses this both for payload unlock and for 'clan vars upload'."
  exit 1
fi

echo "==> Building encrypted bootstrap payload"
TMPDIR="$(mktemp -d /tmp/bootstrap-payload.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/payload/opt/nix-config" "$TMPDIR/payload/bootstrap-secrets"

rsync -a --delete \
  --exclude '.git' \
  --exclude 'result' \
  --exclude 'bootstrap/payload.age' \
  "$ROOT_DIR/" "$TMPDIR/payload/opt/nix-config/"

FONT_ARCHIVE="${BOOTSTRAP_BERKELEY_MONO_FILE:-$ROOT_DIR/bootstrap/berkeley-mono-1.009.zip}"
if [[ -f "$FONT_ARCHIVE" ]]; then
  echo "==> Including Berkeley Mono archive from: $FONT_ARCHIVE"
  cp "$FONT_ARCHIVE" "$TMPDIR/payload/bootstrap-secrets/berkeley-mono-1.009.zip"
else
  echo "==> Berkeley Mono archive not found (optional): $FONT_ARCHIVE"
fi

TAR_PATH="$TMPDIR/payload.tar.gz"
tar -C "$TMPDIR/payload" -czf "$TAR_PATH" .

mapfile -t recipients < <(nix eval --raw --file "$ROOT_DIR/scripts/print-operator-age-recipients.nix")
if [[ "${#recipients[@]}" -eq 0 ]]; then
  echo "ERROR: No operator age recipients found in sops/users/max/key.json"
  exit 1
fi

age_args=()
for recipient in "${recipients[@]}"; do
  [[ -n "$recipient" ]] || continue
  age_args+=("-r" "$recipient")
done

echo "==> Encrypting bootstrap payload to operator recipients from sops/users/max/key.json"
age "${age_args[@]}" -o bootstrap/payload.age "$TAR_PATH"
chmod 600 bootstrap/payload.age

echo "Wrote bootstrap/payload.age"

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

echo "Done. Boot from $DEVICE, connect networking if needed, then run:"
echo "  bootstrap-install <target> <disk>"
echo
echo "If you changed operator keys or generated vars for a new target, make sure this USB was rebuilt after that change."
