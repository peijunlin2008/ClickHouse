#!/usr/bin/env bash
# Tags: no-fasttest
# Tag no-fasttest: Kafka is not available in fast tests

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

KAFKA_TOPIC=$(echo "${CLICKHOUSE_TEST_UNIQUE_NAME}" | tr '_' '-')
KAFKA_GROUP="${CLICKHOUSE_TEST_UNIQUE_NAME}_group"
KAFKA_BROKER="localhost:9092"
KEEPER_PATH="/clickhouse/test/${CLICKHOUSE_TEST_UNIQUE_NAME}"
KAFKA_PRODUCER_OPTS="--producer-property delivery.timeout.ms=30000 --producer-property linger.ms=0"

# Create topic
timeout 30 kafka-topics.sh --bootstrap-server $KAFKA_BROKER --create --topic $KAFKA_TOPIC \
    --partitions 1 --replication-factor 1 2>/dev/null | sed 's/Created topic .*/Created topic./'

# Produce first batch
for i in $(seq 1 3); do
    echo "{\"id\": $i, \"data\": \"batch1_$i\"}"
done | timeout 30 kafka-console-producer.sh --bootstrap-server $KAFKA_BROKER --topic $KAFKA_TOPIC \
    $KAFKA_PRODUCER_OPTS 2>/dev/null

# Create Kafka2 engine table (with keeper path for offset storage)
$CLICKHOUSE_CLIENT --allow_experimental_kafka_offsets_storage_in_keeper 1 -q "
    CREATE TABLE ${CLICKHOUSE_TEST_UNIQUE_NAME}_kafka (id UInt64, data String)
    ENGINE = Kafka
    SETTINGS kafka_broker_list = '$KAFKA_BROKER',
             kafka_topic_list = '$KAFKA_TOPIC',
             kafka_group_name = '$KAFKA_GROUP',
             kafka_format = 'JSONEachRow',
             kafka_max_block_size = 100,
             kafka_keeper_path = '$KEEPER_PATH',
             kafka_replica_name = 'r1';
"

# Create destination table
$CLICKHOUSE_CLIENT -q "
    CREATE TABLE ${CLICKHOUSE_TEST_UNIQUE_NAME}_dst (id UInt64, data String)
    ENGINE = MergeTree ORDER BY id;
"

# Create materialized view
$CLICKHOUSE_CLIENT -q "
    CREATE MATERIALIZED VIEW ${CLICKHOUSE_TEST_UNIQUE_NAME}_mv TO ${CLICKHOUSE_TEST_UNIQUE_NAME}_dst AS
    SELECT * FROM ${CLICKHOUSE_TEST_UNIQUE_NAME}_kafka;
"

# Wait for first batch
for i in $(seq 1 30); do
    count=$($CLICKHOUSE_CLIENT -q "SELECT count() FROM ${CLICKHOUSE_TEST_UNIQUE_NAME}_dst")
    if [ "$count" -ge 3 ]; then
        break
    fi
    sleep 1
done

echo "--- After first batch ---"
$CLICKHOUSE_CLIENT -q "SELECT id, data FROM ${CLICKHOUSE_TEST_UNIQUE_NAME}_dst ORDER BY id"

# Produce second batch
for i in $(seq 4 6); do
    echo "{\"id\": $i, \"data\": \"batch2_$i\"}"
done | timeout 30 kafka-console-producer.sh --bootstrap-server $KAFKA_BROKER --topic $KAFKA_TOPIC \
    $KAFKA_PRODUCER_OPTS 2>/dev/null

# Wait for second batch
for i in $(seq 1 30); do
    count=$($CLICKHOUSE_CLIENT -q "SELECT count() FROM ${CLICKHOUSE_TEST_UNIQUE_NAME}_dst")
    if [ "$count" -ge 6 ]; then
        break
    fi
    sleep 1
done

echo "--- After second batch ---"
$CLICKHOUSE_CLIENT -q "SELECT id, data FROM ${CLICKHOUSE_TEST_UNIQUE_NAME}_dst ORDER BY id"

# Cleanup
$CLICKHOUSE_CLIENT -q "DROP TABLE IF EXISTS ${CLICKHOUSE_TEST_UNIQUE_NAME}_mv"
$CLICKHOUSE_CLIENT -q "DROP TABLE IF EXISTS ${CLICKHOUSE_TEST_UNIQUE_NAME}_dst"
$CLICKHOUSE_CLIENT -q "DROP TABLE IF EXISTS ${CLICKHOUSE_TEST_UNIQUE_NAME}_kafka"
timeout 10 kafka-topics.sh --bootstrap-server $KAFKA_BROKER --delete --topic $KAFKA_TOPIC 2>/dev/null
