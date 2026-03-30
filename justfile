set shell := ["bash", "-euo", "pipefail", "-c"]

# Build and write a bootstrap installer USB with encrypted payload.
# Usage: just write flash /dev/sdX
write target device:
    @if [[ "{{target}}" != "flash" ]]; then \
      echo "Usage: just write flash /dev/sdX"; \
      exit 1; \
    fi
    @./scripts/bootstrap-write-flash.sh {{device}}

# Safer local switch for Clan-managed hosts.
# Preflight gates: vars check, configured sops key exists, test activation works,
# user password secret materialized, and vars hash matches /etc/shadow.
# Usage:
#   just switch <target>
#   just switch <target> --test
switch target *args:
    @mode="switch"; \
    for arg in {{args}}; do \
      if [[ "$arg" == "--test" ]]; then \
        mode="test"; \
      else \
        echo "ERROR: unknown option for switch: $arg"; \
        echo "Usage: just switch <target> [--test]"; \
        exit 1; \
      fi; \
    done; \
    if [[ -z "${SOPS_AGE_KEY_FILE:-}" ]]; then \
      if [[ -f "$HOME/.config/sops/age/keys.txt" ]]; then \
        export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"; \
        echo "==> Using default SOPS age key: $SOPS_AGE_KEY_FILE"; \
      else \
        echo "ERROR: SOPS_AGE_KEY_FILE is not set and default key not found at $HOME/.config/sops/age/keys.txt"; \
        exit 1; \
      fi; \
    fi; \
    echo "==> Checking Clan vars for {{target}}"; \
    CLAN_DIR="$PWD" clan vars check {{target}}; \
    pw="$(CLAN_DIR="$PWD" clan vars get {{target}} user-password-max/user-password)"; \
    echo "==> Login password that should be assigned to user 'max' on {{target}}:"; \
    printf '%s\n' "$pw"; \
    key_path="$(nix eval --raw .#nixosConfigurations.{{target}}.config.sops.age.keyFile)"; \
    echo "==> Checking configured sops key file exists: $key_path"; \
    sudo test -s "$key_path" || { echo "ERROR: Missing or empty sops key file at $key_path"; exit 1; }; \
    echo "==> Running activation preflight (nixos-rebuild test)"; \
    sudo --preserve-env=SOPS_AGE_KEY_FILE,CLAN_DIR CLAN_DIR="$PWD" nixos-rebuild test --flake .#{{target}}; \
    secret_path="/run/secrets-for-users/vars/user-password-max/user-password-hash"; \
    echo "==> Verifying user password secret exists: $secret_path"; \
    sudo test -s "$secret_path" || { echo "ERROR: User password secret missing after test activation"; exit 1; }; \
    expected_hash="$(CLAN_DIR="$PWD" clan vars get {{target}} user-password-max/user-password-hash)"; \
    actual_hash="$(sudo getent shadow max | cut -d: -f2)"; \
    if [[ "$expected_hash" != "$actual_hash" ]]; then \
      echo "ERROR: vars hash does not match /etc/shadow after test activation; refusing $mode"; \
      echo "expected(vars): ${expected_hash:0:24}..."; \
      echo "actual(shadow): ${actual_hash:0:24}..."; \
      exit 1; \
    fi; \
    if [[ "$mode" == "switch" ]]; then \
      echo "==> Preflight passed; switching system to .#{{target}}"; \
      sudo --preserve-env=SOPS_AGE_KEY_FILE,CLAN_DIR CLAN_DIR="$PWD" nixos-rebuild switch --flake .#{{target}}; \
      just diagnose-password {{target}}; \
    else \
      echo "==> Preflight passed; test activation completed for .#{{target}} (no switch performed)"; \
    fi

# Regenerate and replace a machine's hardware-configuration.nix from current host hardware.
# Usage: just update-hardware <target>
update-hardware target:
    @dst="machines/{{target}}/hardware-configuration.nix"; \
    if [[ ! -d "machines/{{target}}" ]]; then \
      echo "ERROR: target machine directory not found: machines/{{target}}"; \
      exit 1; \
    fi; \
    if [[ -f "$dst" ]]; then \
      ts="$(date +%Y%m%d%H%M%S)"; \
      bak="$dst.bak.$ts"; \
      cp "$dst" "$bak"; \
      echo "==> Backed up existing hardware config to $bak"; \
    fi; \
    tmp="$(mktemp)"; \
    trap 'rm -f "$tmp"' EXIT; \
    echo "==> Generating fresh hardware config from current host"; \
    sudo nixos-generate-config --show-hardware-config > "$tmp"; \
    install -Dm644 "$tmp" "$dst"; \
    echo "==> Updated $dst"
