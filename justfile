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
    fi; \
    echo "==> Checking Clan vars for {{target}}"; \
    CLAN_DIR="$PWD" clan vars check {{target}}; \
    pw="$(CLAN_DIR="$PWD" clan vars get {{target}} user-password-max/user-password)"; \
    echo "==> Login password that will be assigned to user 'max' on {{target}}:"; \
    printf '%s\n' "$pw"; \
    echo "==> Switching system to .#{{target}}"; \
    sudo --preserve-env=SOPS_AGE_KEY_FILE,CLAN_DIR CLAN_DIR="$PWD" nixos-rebuild switch --flake .#{{target}}; \
    just diagnose-password {{target}}

# Compare Clan var password/hash with the effective hash in /etc/shadow.
# Usage: just diagnose-password <target>
diagnose-password target:
    @if [[ -z "${SOPS_AGE_KEY_FILE:-}" ]]; then \
      if [[ -f "$HOME/.config/sops/age/keys.txt" ]]; then \
        export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"; \
      else \
        echo "ERROR: SOPS_AGE_KEY_FILE is not set and default key not found at $HOME/.config/sops/age/keys.txt"; \
        exit 1; \
      fi; \
    fi; \
    pw="$(CLAN_DIR="$PWD" clan vars get {{target}} user-password-max/user-password)"; \
    expected_hash="$(CLAN_DIR="$PWD" clan vars get {{target}} user-password-max/user-password-hash)"; \
    actual_hash="$(sudo getent shadow max | cut -d: -f2)"; \
    echo "==> Password diagnostics for max on {{target}}"; \
    echo "expected hash (vars): ${expected_hash:0:24}..."; \
    echo "actual hash (/etc/shadow): ${actual_hash:0:24}..."; \
    if [[ "$expected_hash" == "$actual_hash" ]]; then \
      echo "vars_hash_matches_shadow: true"; \
    else \
      echo "vars_hash_matches_shadow: false"; \
      echo "NOTE: mismatch confirms the closure/system did not apply the same password hash as current vars."; \
    fi

# Deterministic no-switch checks: user/root var visibility + built closure hash.
# Usage: just diagnose-closure-password <target>
diagnose-closure-password target:
    @if [[ -z "${SOPS_AGE_KEY_FILE:-}" ]]; then \
      if [[ -f "$HOME/.config/sops/age/keys.txt" ]]; then \
        export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"; \
      else \
        echo "ERROR: SOPS_AGE_KEY_FILE is not set and default key not found at $HOME/.config/sops/age/keys.txt"; \
        exit 1; \
      fi; \
    fi; \
    echo "==> users.mutableUsers (expected false for declarative password control)"; \
    nix eval --json .#nixosConfigurations.{{target}}.config.users.mutableUsers; \
    echo; \
    expected_user_hash="$(CLAN_DIR="$PWD" clan vars get {{target}} user-password-max/user-password-hash)"; \
    expected_root_hash="$(sudo --preserve-env=CLAN_DIR,SOPS_AGE_KEY_FILE CLAN_DIR="$PWD" clan vars get {{target}} user-password-max/user-password-hash)"; \
    echo "==> vars hash as user : ${expected_user_hash:0:24}..."; \
    echo "==> vars hash as root : ${expected_root_hash:0:24}..."; \
    if [[ "$expected_user_hash" == "$expected_root_hash" ]]; then \
      echo "vars_hash_user_matches_root: true"; \
    else \
      echo "vars_hash_user_matches_root: false"; \
    fi; \
    echo "==> Building closure only (no switch)"; \
    sudo --preserve-env=CLAN_DIR,SOPS_AGE_KEY_FILE CLAN_DIR="$PWD" nixos-rebuild build --flake .#{{target}}; \
    built_hash="$(grep '^max:' ./result/etc/shadow | cut -d: -f2)"; \
    echo "==> built closure /etc/shadow hash: ${built_hash:0:24}..."; \
    if [[ "$built_hash" == "$expected_user_hash" ]]; then \
      echo "built_hash_matches_vars_hash: true"; \
    else \
      echo "built_hash_matches_vars_hash: false"; \
    fi
