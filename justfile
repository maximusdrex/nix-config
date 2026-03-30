set shell := ["bash", "-euo", "pipefail", "-c"]

# Safely switch a local machine config using Clan-managed vars.
# Run this from inside `nix develop .#bootstrap`.
# Usage: just switch <target>
switch target:
    @if [[ -z "${SOPS_AGE_KEY_FILE:-}" ]]; then \
      echo "ERROR: SOPS_AGE_KEY_FILE is not set."; \
      echo "Set it first, e.g.: export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt"; \
      exit 1; \
    fi
    @echo "==> Checking Clan vars for {{target}}"
    CLAN_DIR="$PWD" clan vars check {{target}}
    @echo "==> Switching system to .#{{target}}"
    sudo --preserve-env=SOPS_AGE_KEY_FILE,CLAN_DIR \
      CLAN_DIR="$PWD" \
      nixos-rebuild switch --flake .#{{target}}
