#!/usr/bin/env bash

set -euo pipefail

: "${ANYTYPE_STATE_DIR:?ANYTYPE_STATE_DIR is required}"
: "${ANYTYPE_COORDINATOR_IMAGE:?ANYTYPE_COORDINATOR_IMAGE is required}"
: "${ANYTYPE_PODMAN_NETWORK:?ANYTYPE_PODMAN_NETWORK is required}"

state_dir="$ANYTYPE_STATE_DIR"
identity_dir="$state_dir/identity"
config_dir="$state_dir/config"
rendered_hash_file="$identity_dir/.renderedConfigurationHash"
applied_hash_file="$identity_dir/.appliedConfigurationHash"
applied_id_file="$identity_dir/.appliedConfigurationId"

read_secret() {
  tr -d '\r\n' < "$1"
}

if [[ ! -s "$rendered_hash_file" ]]; then
  echo "The rendered configuration hash is missing." >&2
  exit 1
fi

rendered_hash="$(read_secret "$rendered_hash_file")"

if [[ ! "$rendered_hash" =~ ^[a-f0-9]{64}$ ]]; then
  echo "The rendered configuration hash has an invalid format." >&2
  exit 1
fi

configuration_id=""
applied_hash=""

if [[ -s "$applied_id_file" && -s "$applied_hash_file" ]]; then
  configuration_id="$(read_secret "$applied_id_file")"
  applied_hash="$(read_secret "$applied_hash_file")"
fi

if [[ ! "$configuration_id" =~ ^[a-f0-9]{24}$ || "$applied_hash" != "$rendered_hash" ]]; then
  apply_output="$(
    podman run \
      --name anytype-coordinator-bootstrap \
      --replace \
      --rm \
      --pull missing \
      --network "$ANYTYPE_PODMAN_NETWORK" \
      --volume "$config_dir/any-sync-coordinator:/etc/any-sync-coordinator:Z" \
      "$ANYTYPE_COORDINATOR_IMAGE" \
      /bin/any-sync-confapply \
      -c /etc/any-sync-coordinator/config.yml \
      -n /etc/any-sync-coordinator/network.yml \
      -e
  )"
  printf '%s\n' "$apply_output"

  configuration_id="$(
    printf '%s\n' "$apply_output" | sed -n '/^[a-f0-9]\{24\}$/p' | tail -n 1
  )"

  if [[ ! "$configuration_id" =~ ^[a-f0-9]{24}$ ]]; then
    echo "The coordinator returned an invalid configuration ID." >&2
    exit 1
  fi

  applied_id_tmp="$(mktemp "$identity_dir/.appliedConfigurationId.XXXXXX")"
  applied_hash_tmp="$(mktemp "$identity_dir/.appliedConfigurationHash.XXXXXX")"
  printf '%s\n' "$configuration_id" > "$applied_id_tmp"
  printf '%s\n' "$rendered_hash" > "$applied_hash_tmp"
  chmod 0600 "$applied_id_tmp" "$applied_hash_tmp"
  mv -f "$applied_id_tmp" "$applied_id_file"
  mv -f "$applied_hash_tmp" "$applied_hash_file"
fi

chmod 0600 \
  "$applied_hash_file" \
  "$applied_id_file" \
  "$identity_dir/network.yml" \
  "$identity_dir/nodesProcessed.yml" \
  "$config_dir/any-sync-coordinator/network.yml" \
  "$config_dir/any-sync-node-1/config.yml" \
  "$config_dir/any-sync-coordinator/config.yml" \
  "$config_dir/any-sync-filenode/config.yml" \
  "$config_dir/any-sync-consensusnode/config.yml"
chmod 0644 "$state_dir/client.yml" "$state_dir/client-public.yml"

printf 'Applied Anytype network configuration %s\n' "$configuration_id"
