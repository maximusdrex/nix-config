set shell := ["bash", "-euo", "pipefail", "-c"]

# Build and write a bootstrap installer USB with encrypted payload.
# Usage: just write flash /dev/sdX
write target device:
    @if [[ "{{target}}" != "flash" ]]; then \
      echo "Usage: just write flash /dev/sdX"; \
      exit 1; \
    fi
    @./scripts/bootstrap-write-flash.sh {{device}}

# Show which operator age identity source will be used on this machine.
operator-identity-status:
    @resolved="${AGE_KEYFILE:-$PWD/sops/users/max/fido-identities.txt}"; \
    echo "Resolved operator age identity: $resolved"; \
    if [[ ! -s "$resolved" ]]; then \
      echo "Identity source: missing"; \
      exit 1; \
    fi; \
    if grep -q "AGE-PLUGIN-FIDO2-HMAC" "$resolved"; then \
      echo "Identity source: repo-tracked FIDO identity stub"; \
    else \
      echo "Identity source: file-backed age identity"; \
    fi

# Backward-compatible name while the old command ages out.
sops-identity-status:
    @just operator-identity-status

# Import or refresh the managed Clan age backend machine key for a host.
# Usage:
#   just enroll-machine-age-key max-g14-nix
#   just enroll-machine-age-key max-xps-modal /path/to/key.txt
enroll-machine-age-key machine key_path="":
    @./scripts/enroll-machine-age-key.sh "{{machine}}" "{{key_path}}"

# Restore a machine's runtime age key from the repo-encrypted escrow copy.
# Usage:
#   just restore-machine-age-key max-g14-nix
restore-machine-age-key machine:
    @./scripts/restore-machine-age-key.sh "{{machine}}"

# Sign an SSH user cert using the shared operator CA.
# Usage:
#   just sign-ssh-cert ~/.ssh/id_ed25519_sk.pub
#   just sign-ssh-cert ~/.ssh/id_ed25519_sk.pub +180d max
sign-ssh-cert public_key validity="+180d" principals="max":
    @./scripts/sign-ssh-user-cert.sh "{{public_key}}" "{{validity}}" "{{principals}}"

# Safer local switch for Clan-managed hosts.
# This is a local-machine workflow: it populates `/etc/secret-vars` directly
# via Clan's local `--directory` path, then runs activation checks.
# Remote machines should use `clan machines update`.
# Preflight gates: vars check, local secret upload, machine runtime key matches
# the repo, machine key decrypts a real secret, test activation works, user
# password secret materialized, and vars hash matches /etc/shadow.
# Usage:
#   just switch <target>
#   just switch <target> --test
#   just switch <target> --boot
switch target *args:
    @mode="switch"; \
    for arg in {{args}}; do \
      if [[ "$arg" == "--test" ]]; then \
        [[ "$mode" == "switch" ]] || { echo "ERROR: choose only one of --test or --boot"; exit 1; }; \
        mode="test"; \
      elif [[ "$arg" == "--boot" ]]; then \
        [[ "$mode" == "switch" ]] || { echo "ERROR: choose only one of --test or --boot"; exit 1; }; \
        mode="boot"; \
      else \
        echo "ERROR: unknown option for switch: $arg"; \
        echo "Usage: just switch <target> [--test|--boot]"; \
        exit 1; \
      fi; \
    done; \
    export AGE_KEYFILE="${AGE_KEYFILE:-$PWD/sops/users/max/fido-identities.txt}"; \
    echo "==> Using operator age identity: $AGE_KEYFILE"; \
    echo "==> Checking Clan vars for {{target}}"; \
    CLAN_DIR="$PWD" clan vars check {{target}}; \
    echo "==> Populating local /etc/secret-vars for {{target}}"; \
    sudo rm -rf /etc/secret-vars; \
    sudo install -d -m 700 /etc/secret-vars; \
    sudo --preserve-env=AGE_KEYFILE,CLAN_DIR CLAN_DIR="$PWD" clan vars upload {{target}} --directory /etc/secret-vars; \
    repo_key_path="secrets/age-keys/machines/{{target}}/pub"; \
    echo "==> Verifying local runtime machine key matches $repo_key_path"; \
    test -s "$repo_key_path" || { echo "ERROR: missing repo machine public key: $repo_key_path"; exit 1; }; \
    sudo test -s /etc/secret-vars/key.txt || { echo "ERROR: missing runtime machine key at /etc/secret-vars/key.txt after local upload"; exit 1; }; \
    repo_machine_pub="$(tr -d '\n' < "$repo_key_path")"; \
    host_machine_pub="$(sudo age-keygen -y /etc/secret-vars/key.txt | tr -d '\n')"; \
    if [[ "$repo_machine_pub" != "$host_machine_pub" ]]; then \
      echo "ERROR: runtime machine key on host does not match repo machine key"; \
      echo "repo : $repo_machine_pub"; \
      echo "host : $host_machine_pub"; \
      exit 1; \
    fi; \
    expected_hash="$(CLAN_DIR="$PWD" clan vars get {{target}} user-password-max/user-password-hash)"; \
    encrypted_hash_path="secrets/clan-vars/per-machine/{{target}}/user-password-max/user-password-hash/user-password-hash.age"; \
    echo "==> Verifying machine key decrypts $encrypted_hash_path"; \
    test -s "$encrypted_hash_path" || { echo "ERROR: missing encrypted secret payload: $encrypted_hash_path"; exit 1; }; \
    decrypted_hash="$(sudo age --decrypt -i /etc/secret-vars/key.txt "$encrypted_hash_path")"; \
    if [[ "$decrypted_hash" != "$expected_hash" ]]; then \
      echo "ERROR: machine key decrypted secret does not match Clan vars"; \
      echo "expected(vars): ${expected_hash:0:24}..."; \
      echo "decrypted(key): ${decrypted_hash:0:24}..."; \
      exit 1; \
    fi; \
    pw="$(CLAN_DIR="$PWD" clan vars get {{target}} user-password-max/user-password)"; \
    echo "==> Login password that should be assigned to user 'max' on {{target}}:"; \
    printf '%s\n' "$pw"; \
    if [[ -L /run/secrets && "$mode" != "boot" ]]; then \
      echo "ERROR: current system still owns /run/secrets via the old sops-nix symlink."; \
      echo "Run 'just switch {{target}} --boot' once, reboot into the new generation, then rerun 'just switch {{target}}'."; \
      exit 1; \
    fi; \
    if [[ "$mode" != "boot" ]]; then \
      echo "==> Cleaning up any stale Clan secret temp mounts"; \
      for tmp in /run/user-secrets.tmp /run/secrets.tmp; do \
        if sudo mountpoint -q "$tmp"; then \
          sudo umount -R "$tmp" 2>/dev/null || sudo umount --lazy "$tmp" 2>/dev/null || true; \
        fi; \
        sudo rm -rf "$tmp"; \
      done; \
    fi; \
    if [[ "$mode" == "boot" ]]; then \
      echo "==> Installing .#{{target}} as the next boot generation"; \
      sudo --preserve-env=AGE_KEYFILE,CLAN_DIR CLAN_DIR="$PWD" nixos-rebuild boot --flake .#{{target}}; \
      echo "==> Boot generation installed. Reboot into it, then rerun 'just switch {{target}}'."; \
      exit 0; \
    fi; \
    echo "==> Running activation preflight (nixos-rebuild test)"; \
    sudo --preserve-env=AGE_KEYFILE,CLAN_DIR CLAN_DIR="$PWD" nixos-rebuild test --flake .#{{target}}; \
    secret_path="$(nix eval --raw .#nixosConfigurations.{{target}}.config.users.users.max.hashedPasswordFile)"; \
    echo "==> Verifying user password secret exists: $secret_path"; \
    sudo test -s "$secret_path" || { echo "ERROR: User password secret missing after test activation"; exit 1; }; \
    actual_hash="$(sudo getent shadow max | cut -d: -f2)"; \
    if [[ "$expected_hash" != "$actual_hash" ]]; then \
      echo "ERROR: vars hash does not match /etc/shadow after test activation; refusing $mode"; \
      echo "expected(vars): ${expected_hash:0:24}..."; \
      echo "actual(shadow): ${actual_hash:0:24}..."; \
      exit 1; \
    fi; \
    if [[ "$mode" == "switch" ]]; then \
      echo "==> Preflight passed; switching system to .#{{target}}"; \
      sudo --preserve-env=AGE_KEYFILE,CLAN_DIR CLAN_DIR="$PWD" nixos-rebuild switch --flake .#{{target}}; \
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
    @export AGE_KEYFILE="${AGE_KEYFILE:-$PWD/sops/users/max/fido-identities.txt}"; \
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
    @export AGE_KEYFILE="${AGE_KEYFILE:-$PWD/sops/users/max/fido-identities.txt}"; \
    echo "==> users.mutableUsers (expected false for declarative password control)"; \
    nix eval --json .#nixosConfigurations.{{target}}.config.users.mutableUsers; \
    echo; \
    expected_user_hash="$(CLAN_DIR="$PWD" clan vars get {{target}} user-password-max/user-password-hash)"; \
    expected_root_hash="$(sudo --preserve-env=CLAN_DIR,AGE_KEYFILE CLAN_DIR="$PWD" clan vars get {{target}} user-password-max/user-password-hash)"; \
    echo "==> vars hash as user : ${expected_user_hash:0:24}..."; \
    echo "==> vars hash as root : ${expected_root_hash:0:24}..."; \
    if [[ "$expected_user_hash" == "$expected_root_hash" ]]; then \
      echo "vars_hash_user_matches_root: true"; \
    else \
      echo "vars_hash_user_matches_root: false"; \
    fi; \
    echo "==> Building closure only (no switch)"; \
    sudo --preserve-env=CLAN_DIR,AGE_KEYFILE CLAN_DIR="$PWD" nixos-rebuild build --flake .#{{target}}; \
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
