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
      echo "ERROR: vars hash does not match /etc/shadow after test activation; refusing switch"; \
      echo "expected(vars): ${expected_hash:0:24}..."; \
      echo "actual(shadow): ${actual_hash:0:24}..."; \
      exit 1; \
    fi; \
    echo "==> Preflight passed; switching system to .#{{target}}"; \
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
    configured_hash_json="$(nix eval --json .#nixosConfigurations.{{target}}.config.users.users.max.hashedPassword)"; \
    configured_hash_file_json="$(nix eval --json .#nixosConfigurations.{{target}}.config.users.users.max.hashedPasswordFile)"; \
    echo "==> config.users.users.max.hashedPassword: $configured_hash_json"; \
    echo "==> config.users.users.max.hashedPasswordFile: $configured_hash_file_json"; \
    if [[ "$configured_hash_json" != "null" ]]; then \
      configured_hash="$(nix eval --raw .#nixosConfigurations.{{target}}.config.users.users.max.hashedPassword)"; \
      if [[ "$configured_hash" == "$expected_user_hash" ]]; then \
        echo "configured_hash_matches_vars_hash: true"; \
      else \
        echo "configured_hash_matches_vars_hash: false"; \
      fi; \
    fi; \
    if [[ "$configured_hash_file_json" != "null" ]]; then \
      configured_hash_file="$(nix eval --raw .#nixosConfigurations.{{target}}.config.users.users.max.hashedPasswordFile)"; \
      if sudo test -f "$configured_hash_file"; then \
        runtime_hash_file_value="$(sudo cat "$configured_hash_file")"; \
        echo "==> runtime hash file value: ${runtime_hash_file_value:0:24}..."; \
        if [[ "$runtime_hash_file_value" == "$expected_user_hash" ]]; then \
          echo "runtime_hash_file_matches_vars_hash: true"; \
        else \
          echo "runtime_hash_file_matches_vars_hash: false"; \
        fi; \
      else \
        echo "NOTE: configured hash file path does not exist on current system: $configured_hash_file"; \
      fi; \
    fi
