#!/usr/bin/env bash
set -euo pipefail

# Resolves a usable SOPS_AGE_KEY_FILE path for either file-backed age keys
# or FIDO-backed age identities.
#
# Priority:
#  1) explicit SOPS_AGE_KEY_FILE (if non-empty file)
#  2) explicit SOPS_AGE_FIDO_IDENTITY_FILE (if non-empty file)
#  3) ~/.config/sops/age/keys.txt
#  4) ~/.config/sops/age/fido2-identity.txt
#
# Prints the resolved path to stdout.

if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]]; then
  if [[ -s "${SOPS_AGE_KEY_FILE}" ]]; then
    printf '%s\n' "${SOPS_AGE_KEY_FILE}"
    exit 0
  fi
  echo "ERROR: SOPS_AGE_KEY_FILE is set but not readable/non-empty: ${SOPS_AGE_KEY_FILE}" >&2
  exit 1
fi

if [[ -n "${SOPS_AGE_FIDO_IDENTITY_FILE:-}" ]]; then
  if [[ -s "${SOPS_AGE_FIDO_IDENTITY_FILE}" ]]; then
    printf '%s\n' "${SOPS_AGE_FIDO_IDENTITY_FILE}"
    exit 0
  fi
  echo "ERROR: SOPS_AGE_FIDO_IDENTITY_FILE is set but not readable/non-empty: ${SOPS_AGE_FIDO_IDENTITY_FILE}" >&2
  exit 1
fi

for candidate in \
  "$HOME/.config/sops/age/keys.txt" \
  "$HOME/.config/sops/age/fido2-identity.txt"
  do
  if [[ -s "$candidate" ]]; then
    printf '%s\n' "$candidate"
    exit 0
  fi
done

echo "ERROR: could not resolve SOPS age identity file." >&2
echo "Set SOPS_AGE_KEY_FILE (file key or plugin identity), or SOPS_AGE_FIDO_IDENTITY_FILE." >&2
echo "Tried defaults:" >&2
echo "  - $HOME/.config/sops/age/keys.txt" >&2
echo "  - $HOME/.config/sops/age/fido2-identity.txt" >&2
exit 1
