set shell := ["bash", "-euo", "pipefail", "-c"]

# Safely switch a local machine config using Clan-managed vars.
# Run this from inside `nix develop .#bootstrap`.
# Usage: just switch <target>
switch target:
    @if [[ -z "${SOPS_AGE_KEY_FILE:-}" ]]; then \
      if [[ -f "$HOME/.config/sops/age/keys.txt" ]]; then \
        export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"; \
        echo "==> Using default SOPS age key: $SOPS_AGE_KEY_FILE"; \
      else \
        echo "ERROR: SOPS_AGE_KEY_FILE is not set and default key not found at $HOME/.config/sops/age/keys.txt"; \
        exit 1; \
      fi; \
    fi
    @echo "==> Checking Clan vars for {{target}}"
    CLAN_DIR="$PWD" clan vars check {{target}}
    @echo "==> Login password that will be set for user 'max' on {{target}}:"
    @CLAN_DIR="$PWD" clan vars get {{target}} user-password-max/user-password
    @echo "==> Switching system to .#{{target}}"
    sudo --preserve-env=SOPS_AGE_KEY_FILE,CLAN_DIR \
      CLAN_DIR="$PWD" \
      nixos-rebuild switch --flake .#{{target}}
