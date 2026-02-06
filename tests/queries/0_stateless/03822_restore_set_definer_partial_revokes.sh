#!/usr/bin/env bash
# Tags: no-parallel

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

user_name="restore_tester_03822_${CLICKHOUSE_DATABASE}"
role_name="test_role_03822_${CLICKHOUSE_DATABASE}"
role2_name="test_role2_03822_${CLICKHOUSE_DATABASE}"
backup_name="Disk('backups', '${CLICKHOUSE_TEST_UNIQUE_NAME}')"

${CLICKHOUSE_CLIENT} --query "DROP USER IF EXISTS ${user_name}"
${CLICKHOUSE_CLIENT} --query "DROP ROLE IF EXISTS ${role_name}"
${CLICKHOUSE_CLIENT} --query "DROP ROLE IF EXISTS ${role2_name}"

${CLICKHOUSE_CLIENT} --query "CREATE USER ${user_name}"
${CLICKHOUSE_CLIENT} --query "GRANT CREATE ROLE ON *.* TO ${user_name}"
${CLICKHOUSE_CLIENT} --query "GRANT ROLE ADMIN ON *.* TO ${user_name}"
${CLICKHOUSE_CLIENT} --query "GRANT SET DEFINER ON * TO ${user_name} WITH GRANT OPTION"
${CLICKHOUSE_CLIENT} --query "REVOKE SET DEFINER ON \`internal-user-1\` FROM ${user_name}"

# Create a role that will be backed up.
# Role has SET_DEFINER ON * with 3 revokes.
${CLICKHOUSE_CLIENT} --query "CREATE ROLE ${role_name}"
${CLICKHOUSE_CLIENT} --query "GRANT SET DEFINER ON * TO ${role_name} WITH GRANT OPTION"
${CLICKHOUSE_CLIENT} --query "REVOKE SET DEFINER ON \`internal-user-1\` FROM ${role_name}"
${CLICKHOUSE_CLIENT} --query "REVOKE SET DEFINER ON \`internal-user-2\` FROM ${role_name}"
${CLICKHOUSE_CLIENT} --query "REVOKE SET DEFINER ON \`internal-user-3\` FROM ${role_name}"

# Create a second role that depends on the first.
${CLICKHOUSE_CLIENT} --query "CREATE ROLE ${role2_name}"
${CLICKHOUSE_CLIENT} --query "GRANT ${role_name} TO ${role2_name}"

${CLICKHOUSE_CLIENT} --query "BACKUP TABLE system.roles TO ${backup_name}" | grep -o "BACKUP_CREATED"

${CLICKHOUSE_CLIENT} --query "DROP ROLE ${role_name}"
${CLICKHOUSE_CLIENT} --query "DROP ROLE ${role2_name}"

${CLICKHOUSE_CLIENT} --user "${user_name}" --query "RESTORE ALL FROM ${backup_name} SETTINGS allow_non_empty_tables=true" | grep -o "RESTORED"

echo "Restored role grants:"
${CLICKHOUSE_CLIENT} --query "SHOW GRANTS FOR ${role_name}" | sed "s/${role_name}/test_role/g"
