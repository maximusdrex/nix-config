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

for cmd in nix age tar git; do
  command -v "$cmd" >/dev/null || { echo "Missing command: $cmd"; exit 1; }
done

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p bootstrap

echo "==> Insert your hardware key now."
read -r -p "Press Enter when ready... " _

recipient=""
if command -v age-plugin-yubikey >/dev/null 2>&1; then
  recipient="$(age-plugin-yubikey --list 2>/dev/null | awk '/^age1yubikey/{print $1; exit}')" || true
fi

if [[ -z "$recipient" && -f bootstrap/yubikey-recipient.txt ]]; then
  recipient="$(head -n1 bootstrap/yubikey-recipient.txt | tr -d '[:space:]')"
fi

if [[ -z "$recipient" ]]; then
  read -r -p "Enter Age recipient for your hardware key (age1...): " recipient
fi

if [[ -z "$recipient" ]]; then
  echo "ERROR: No recipient provided"
  exit 1
fi

echo "==> Building encrypted bootstrap payload"
TMP_TAR="$(mktemp /tmp/bootstrap-payload.XXXXXX.tar.gz)"
trap 'rm -f "$TMP_TAR"' EXIT

tar -C "$ROOT_DIR" -czf "$TMP_TAR" \
  flake.nix flake.lock clan.nix justfile \
  machines homes roles modules overlays packages clanServices vars sops scripts

age -r "$recipient" -o bootstrap/payload.age "$TMP_TAR"
echo "Wrote bootstrap/payload.age"

echo "==> Building bootstrap installer ISO"
nix build .#bootstrap-installer-iso
ISO_PATH="$(readlink -f result/iso/max-bootstrap-installer.iso)"

echo "==> About to erase and write $DEVICE with $ISO_PATH"
read -r -p "Type YES to continue: " confirm
[[ "$confirm" == "YES" ]] || { echo "Aborted"; exit 1; }

sudo dd if="$ISO_PATH" of="$DEVICE" bs=4M conv=fsync status=progress
sync

echo "Done. Boot from $DEVICE, then run: bootstrap-unlock"
