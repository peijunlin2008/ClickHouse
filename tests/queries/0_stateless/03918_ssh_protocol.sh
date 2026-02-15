#!/usr/bin/env bash
# Tags: no-fasttest

CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CURDIR"/../shell_config.sh

# Test SSH protocol support: connect via SSH and run queries.

# Check that the SSH port is configured and listening
if ! echo "" | nc -w 1 "${CLICKHOUSE_HOST}" "${CLICKHOUSE_PORT_SSH}" >/dev/null 2>&1; then
    echo "SSH port ${CLICKHOUSE_PORT_SSH} is not available, skipping test" >&2
    exit 0
fi

# Check that the ssh client is available
if ! command -v ssh &>/dev/null; then
    echo "ssh client is not available, skipping test" >&2
    exit 0
fi

SSH_USER_KEY="$CURDIR/../../config/ssh_user_ed25519_key"

# Extract the base64 public key from the .pub file
SSH_USER_PUBKEY=$(awk '{print $2}' "$SSH_USER_KEY.pub")

SSH_USER="ssh_user_${CLICKHOUSE_TEST_UNIQUE_NAME}"

# Create a user with SSH key authentication
${CLICKHOUSE_CLIENT} --query "DROP USER IF EXISTS ${SSH_USER}"
${CLICKHOUSE_CLIENT} --query "CREATE USER ${SSH_USER} IDENTIFIED WITH ssh_key BY KEY '${SSH_USER_PUBKEY}' TYPE 'ssh-ed25519'"
${CLICKHOUSE_CLIENT} --query "GRANT ALL ON ${CLICKHOUSE_DATABASE}.* TO ${SSH_USER}"

# Run queries via SSH
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_USER_KEY" \
    -p "${CLICKHOUSE_PORT_SSH}" \
    "${SSH_USER}@${CLICKHOUSE_HOST}" \
    "SELECT 1" 2>/dev/null

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_USER_KEY" \
    -p "${CLICKHOUSE_PORT_SSH}" \
    "${SSH_USER}@${CLICKHOUSE_HOST}" \
    "SELECT currentUser() = '${SSH_USER}'" 2>/dev/null

# Clean up
${CLICKHOUSE_CLIENT} --query "DROP USER IF EXISTS ${SSH_USER}"
