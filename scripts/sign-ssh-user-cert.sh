#!/usr/bin/env bash
set -euo pipefail

PUBLIC_KEY="${1:-}"
VALIDITY="${2:-+180d}"
PRINCIPALS="${3:-max}"

if [[ -z "$PUBLIC_KEY" ]]; then
  echo "Usage: $0 <public-key-path> [validity] [principals]"
  echo "Example: $0 ~/.ssh/id_ed25519_sk.pub +180d max"
  exit 1
fi

if [[ ! -f "$PUBLIC_KEY" ]]; then
  echo "ERROR: public key not found: $PUBLIC_KEY"
  exit 1
fi

for cmd in clan hostname ssh-keygen mktemp date; do
  command -v "$cmd" >/dev/null || {
    echo "ERROR: missing command: $cmd"
    echo "Hint: run inside 'nix develop .#bootstrap' if clan-cli is unavailable."
    exit 1
  }
done

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${AGE_KEYFILE:-}" && -f "$ROOT_DIR/sops/users/max/fido-identities.txt" ]]; then
  export AGE_KEYFILE="$ROOT_DIR/sops/users/max/fido-identities.txt"
fi

TMPDIR="$(mktemp -d /tmp/sign-ssh-user-cert.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

CA_KEY="$TMPDIR/openssh-ca"
IDENTITY="${SIGN_SSH_CERT_IDENTITY:-${USER:-max}-$(date -u +%Y%m%d%H%M%S)}"
CA_CONTEXT_MACHINE="${CLAN_SSH_CA_MACHINE:-$(hostname)}"

if ! CLAN_DIR="${CLAN_DIR:-$ROOT_DIR}" clan vars get "$CA_CONTEXT_MACHINE" openssh-ca/id_ed25519 > "$CA_KEY"; then
  echo "ERROR: failed to read openssh-ca/id_ed25519 through Clan vars."
  echo "Set CLAN_SSH_CA_MACHINE to a machine that has access to that shared var."
  exit 1
fi

chmod 600 "$CA_KEY"

ssh-keygen -s "$CA_KEY" -I "$IDENTITY" -n "$PRINCIPALS" -V "$VALIDITY" "$PUBLIC_KEY"

case "$PUBLIC_KEY" in
  *.pub) CERT_PATH="${PUBLIC_KEY%.pub}-cert.pub" ;;
  *) CERT_PATH="${PUBLIC_KEY}-cert.pub" ;;
esac

echo "Wrote SSH user certificate: $CERT_PATH"
echo "Certificate identity: $IDENTITY"
echo "Principals: $PRINCIPALS"
echo "Validity: $VALIDITY"
