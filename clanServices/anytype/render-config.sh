#!/usr/bin/env bash

set -euo pipefail

: "${ANYTYPE_STATE_DIR:?ANYTYPE_STATE_DIR is required}"
: "${ANYTYPE_TEMPLATE_DIR:?ANYTYPE_TEMPLATE_DIR is required}"
: "${ANYTYPE_EXTERNAL_HOSTS:?ANYTYPE_EXTERNAL_HOSTS is required}"
: "${ANYTYPE_STORAGE_HOST:?ANYTYPE_STORAGE_HOST is required}"
: "${ANYTYPE_FILE_DEFAULT_LIMIT:?ANYTYPE_FILE_DEFAULT_LIMIT is required}"
: "${ANYTYPE_SHARED_SPACES_LIMIT:?ANYTYPE_SHARED_SPACES_LIMIT is required}"
: "${CREDENTIALS_DIRECTORY:?CREDENTIALS_DIRECTORY is required}"

state_dir="$ANYTYPE_STATE_DIR"
template_dir="$ANYTYPE_TEMPLATE_DIR"
storage_host="$ANYTYPE_STORAGE_HOST"
identity_dir="$state_dir/identity"
config_dir="$state_dir/config"

access_key="$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/minio-access-key")"
secret_key="$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/minio-secret-key")"
mongo_password="$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/mongo-password")"
redis_password="$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/redis-password")"
network_id="$(tr -d '\n' < "$identity_dir/.networkId")"
network_signing_key="$(tr -d '\n' < "$identity_dir/.networkSigningKey")"

if [[ ! "$access_key" =~ ^[a-f0-9]{32}$ ]]; then
  echo "The MinIO access key has an invalid format." >&2
  exit 1
fi

if [[ ! "$secret_key" =~ ^[a-f0-9]{64}$ ]]; then
  echo "The MinIO secret key has an invalid format." >&2
  exit 1
fi

if [[ ! "$mongo_password" =~ ^[a-f0-9]{64}$ ]]; then
  echo "The MongoDB password has an invalid format." >&2
  exit 1
fi

if [[ ! "$redis_password" =~ ^[a-f0-9]{64}$ ]]; then
  echo "The Redis password has an invalid format." >&2
  exit 1
fi

mapfile -t external_hosts < <(
  printf '%s' "$ANYTYPE_EXTERNAL_HOSTS" | yq eval --unwrapScalar '.[]' -
)

if (( ${#external_hosts[@]} == 0 )); then
  echo "The external host list is empty." >&2
  exit 1
fi

for required_file in nodes.yml account0.yml account1.yml account2.yml account3.yml; do
  if [[ ! -s "$identity_dir/$required_file" ]]; then
    echo "The identity file is missing: $required_file" >&2
    exit 1
  fi
done

install -d -m 0755 "$state_dir"
install -d -m 0700 \
  "$identity_dir" \
  "$config_dir" \
  "$config_dir/.aws" \
  "$config_dir/any-sync-node-1" \
  "$config_dir/any-sync-coordinator" \
  "$config_dir/any-sync-filenode" \
  "$config_dir/any-sync-consensusnode"

for account_file in account1.yml account3.yml; do
  NETWORK_SIGNING_KEY="$network_signing_key" \
    yq eval --inplace '.account.signingKey = strenv(NETWORK_SIGNING_KEY)' \
    "$identity_dir/$account_file"

  NETWORK_SIGNING_KEY="$network_signing_key" \
    yq eval --exit-status '.account.signingKey == strenv(NETWORK_SIGNING_KEY)' \
    "$identity_dir/$account_file" >/dev/null
done

nodes_processed_tmp="$(mktemp "$identity_dir/nodesProcessed.yml.XXXXXX")"
NETWORK_ID="$network_id" \
  yq eval --indent 2 '
    .networkId = strenv(NETWORK_ID) |
    del(.creationTime)
  ' "$identity_dir/nodes.yml" > "$nodes_processed_tmp"

for ((host_index = ${#external_hosts[@]} - 1; host_index >= 0; host_index--)); do
  external_host="${external_hosts[$host_index]}"
  EXTERNAL_HOST="$external_host" \
    yq eval --inplace --indent 2 '
    .nodes[0].addresses = [
      strenv(EXTERNAL_HOST) + ":1001",
      "quic://" + strenv(EXTERNAL_HOST) + ":1011"
    ] + .nodes[0].addresses |
    .nodes[1].addresses = [
      strenv(EXTERNAL_HOST) + ":1004",
      "quic://" + strenv(EXTERNAL_HOST) + ":1014"
    ] + .nodes[1].addresses |
    .nodes[2].addresses = [
      strenv(EXTERNAL_HOST) + ":1005",
      "quic://" + strenv(EXTERNAL_HOST) + ":1015"
    ] + .nodes[2].addresses |
    .nodes[3].addresses = [
      strenv(EXTERNAL_HOST) + ":1006",
      "quic://" + strenv(EXTERNAL_HOST) + ":1016"
    ] + .nodes[3].addresses
    ' "$nodes_processed_tmp"
done

yq eval --exit-status '
  (.nodes | length) == 4 and
  .nodes[0].types[0] == "tree" and
  .nodes[1].types[0] == "coordinator" and
  .nodes[2].types[0] == "file" and
  .nodes[3].types[0] == "consensus"
' "$nodes_processed_tmp" >/dev/null

chmod 0600 "$nodes_processed_tmp"
mv -f "$nodes_processed_tmp" "$identity_dir/nodesProcessed.yml"

network_file_tmp="$(mktemp "$identity_dir/network.yml.XXXXXX")"
yq eval --indent 2 '{"network": .}' \
  "$identity_dir/nodesProcessed.yml" > "$network_file_tmp"
chmod 0600 "$network_file_tmp"
mv -f "$network_file_tmp" "$identity_dir/network.yml"

replace_placeholder() {
  local file="$1"
  local name="$2"
  local value="$3"

  PLACEHOLDER="$name" REPLACEMENT="$value" \
    perl -0pi -e 's/\Q%$ENV{PLACEHOLDER}%\E/$ENV{REPLACEMENT}/g' "$file"
}

replace_all_placeholders() {
  local file="$1"

  replace_placeholder "$file" ANY_SYNC_NODE_1_ADDRESSES "[::]:1001"
  replace_placeholder "$file" ANY_SYNC_NODE_1_QUIC_ADDRESSES "[::]:1011"
  replace_placeholder "$file" ANY_SYNC_COORDINATOR_ADDRESSES "[::]:1004"
  replace_placeholder "$file" ANY_SYNC_COORDINATOR_QUIC_ADDRESSES "[::]:1014"
  replace_placeholder "$file" ANY_SYNC_FILENODE_ADDRESSES "[::]:1005"
  replace_placeholder "$file" ANY_SYNC_FILENODE_QUIC_ADDRESSES "[::]:1015"
  replace_placeholder "$file" ANY_SYNC_CONSENSUSNODE_ADDRESSES "[::]:1006"
  replace_placeholder "$file" ANY_SYNC_CONSENSUSNODE_QUIC_ADDRESSES "[::]:1016"
  replace_placeholder "$file" ANY_SYNC_COORDINATOR_DEFAULT_LIMITS_SPACE_MEMBERS_READ "1000"
  replace_placeholder "$file" ANY_SYNC_COORDINATOR_DEFAULT_LIMITS_SPACE_MEMBERS_WRITE "1000"
  replace_placeholder "$file" ANY_SYNC_COORDINATOR_DEFAULT_LIMITS_SHARED_SPACES_LIMIT "$ANYTYPE_SHARED_SPACES_LIMIT"
  replace_placeholder "$file" ANY_SYNC_FILENODE_DEFAULT_LIMIT "$ANYTYPE_FILE_DEFAULT_LIMIT"
  replace_placeholder "$file" MONGO_CONNECT "mongodb://anytype:$mongo_password@$storage_host:27001/?authSource=admin&replicaSet=rs0"
  replace_placeholder "$file" MONGO_CONNECT_CONSENSUS "mongodb://anytype:$mongo_password@$storage_host:27001/?authSource=admin&replicaSet=rs0&w=majority"
  replace_placeholder "$file" REDIS_URL "redis://:$redis_password@$storage_host:6379?dial_timeout=3&read_timeout=6s"
  replace_placeholder "$file" MINIO_HOST "$storage_host"
  replace_placeholder "$file" MINIO_PORT "9000"
  replace_placeholder "$file" MINIO_BUCKET "minio-bucket"
  replace_placeholder "$file" AWS_ACCESS_KEY_ID "$access_key"
  replace_placeholder "$file" AWS_SECRET_ACCESS_KEY "$secret_key"

  if grep --quiet --extended-regexp '%[A-Z0-9_]+%' "$file"; then
    echo "The rendered file contains an unresolved placeholder: $file" >&2
    exit 1
  fi
}

render_config() {
  local output="$1"
  local account="$2"
  local service_template="$3"
  local output_tmp

  output_tmp="$(mktemp "$output.XXXXXX")"
  cat \
    "$identity_dir/network.yml" \
    "$template_dir/common.yml" \
    "$identity_dir/$account" \
    "$template_dir/$service_template" \
    > "$output_tmp"
  replace_all_placeholders "$output_tmp"
  yq eval --inplace --indent 2 '.' "$output_tmp"
  chmod 0600 "$output_tmp"
  mv -f "$output_tmp" "$output"
}

render_config \
  "$config_dir/any-sync-node-1/config.yml" \
  account0.yml \
  node-1.yml
render_config \
  "$config_dir/any-sync-coordinator/config.yml" \
  account1.yml \
  coordinator.yml
render_config \
  "$config_dir/any-sync-filenode/config.yml" \
  account2.yml \
  filenode.yml
render_config \
  "$config_dir/any-sync-consensusnode/config.yml" \
  account3.yml \
  consensusnode.yml

install -m 0600 \
  "$identity_dir/nodesProcessed.yml" \
  "$config_dir/any-sync-coordinator/network.yml"

aws_credentials_tmp="$(mktemp "$config_dir/.aws/credentials.XXXXXX")"
install -m 0600 "$template_dir/aws-credentials" "$aws_credentials_tmp"
replace_all_placeholders "$aws_credentials_tmp"
mv -f "$aws_credentials_tmp" "$config_dir/.aws/credentials"

install -m 0644 "$identity_dir/nodesProcessed.yml" "$state_dir/client.yml"
chmod 0600 "$identity_dir"/* "$identity_dir"/.[!.]*
