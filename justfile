set shell := ["bash", "-euo", "pipefail", "-c"]

# Build and write a bootstrap installer USB with encrypted payload.
# Usage: just write flash /dev/sdX
write target device:
    @if [[ "{{target}}" != "flash" ]]; then \
      echo "Usage: just write flash /dev/sdX"; \
      exit 1; \
    fi
    @./scripts/bootstrap-write-flash.sh {{device}}

# Show which SOPS age identity file will be used on this machine.
sops-identity-status:
    @resolved="$($PWD/scripts/resolve-sops-age-key-file.sh)"; \
    echo "Resolved SOPS_AGE_KEY_FILE: $resolved"; \
    if grep -q "AGE-PLUGIN-FIDO2-HMAC" "$resolved"; then \
      echo "Identity type: FIDO plugin identity"; \
    else \
      echo "Identity type: file-backed age identity"; \
    fi

# Check recipient policy coverage in vars/ and sops/secrets/.
# Usage:
#   REQUIRED_OPERATOR_RECIPIENTS="age1..." REQUIRED_RECOVERY_RECIPIENTS="age1..." just audit-recipients
audit-recipients:
    @./scripts/audit-sops-recipients.sh

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
    export SOPS_AGE_KEY_FILE="$($PWD/scripts/resolve-sops-age-key-file.sh)"; \
    echo "==> Using SOPS age identity file: $SOPS_AGE_KEY_FILE"; \
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

# Compare Clan var password/hash with the effective hash in /etc/shadow.
# Usage: just diagnose-password <target>
diagnose-password target:
    @export SOPS_AGE_KEY_FILE="$($PWD/scripts/resolve-sops-age-key-file.sh)"; \
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
    @export SOPS_AGE_KEY_FILE="$($PWD/scripts/resolve-sops-age-key-file.sh)"; \
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
