#!/bin/bash

set -euxf -o pipefail

KAFKA_BROKER=${KAFKA_BROKER:-localhost:9092}
KAFKA_VERSION=${KAFKA_VERSION:-3.9.0}
SCALA_VERSION=${SCALA_VERSION:-2.13}
KEEPER_PORT=${KEEPER_PORT:-9181}

find_arch() {
    local arch
    case $(uname -m) in
        x86_64)
            arch="amd64"
            ;;
        aarch64)
            arch="arm64"
            ;;
        *)
            echo "unknown architecture $(uname -m)"
            exit 1
            ;;
    esac
    echo "${arch}"
}

download_kafka() {
    local kafka_dir="/opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION}"
    if [ -d "$kafka_dir" ]; then
        echo "Kafka already installed at $kafka_dir"
        return
    fi
    echo "Downloading Kafka ${KAFKA_VERSION}..."
    curl -fsSL "https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz" \
        | tar -xz -C /opt/
    ln -sf "$kafka_dir" /opt/kafka
    export KAFKA_HOME=/opt/kafka
    export PATH="${KAFKA_HOME}/bin:${PATH}"
}

write_kafka_config() {
    local config_file="$1"
    cat > "$config_file" <<EOF
broker.id=1
listeners=PLAINTEXT://localhost:9092
advertised.listeners=PLAINTEXT://localhost:9092
zookeeper.connect=localhost:${KEEPER_PORT}
log.dirs=/tmp/kafka-logs
num.partitions=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
auto.create.topics.enable=false
log.retention.hours=1
EOF
}

start_kafka() {
    local config_file="/tmp/kafka-server.properties"
    write_kafka_config "$config_file"

    rm -rf /tmp/kafka-logs

    export KAFKA_HEAP_OPTS="-Xmx256m -Xms256m"

    echo "Starting Kafka broker..."
    nohup kafka-server-start.sh "$config_file" > /tmp/kafka.log 2>&1 &
    echo "Kafka started with PID $!"
}

wait_for_kafka() {
    local max_attempts=60
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if kafka-topics.sh --bootstrap-server "$KAFKA_BROKER" --list > /dev/null 2>&1; then
            echo "Kafka is ready"
            return 0
        fi
        echo "Waiting for Kafka to be ready (attempt $((attempt + 1))/$max_attempts)..."
        sleep 1
        attempt=$((attempt + 1))
    done
    echo "ERROR: Kafka failed to start within ${max_attempts} seconds"
    cat /tmp/kafka.log || true
    return 1
}

main() {
    if ! command -v kafka-server-start.sh &> /dev/null; then
        download_kafka
    fi
    start_kafka
    wait_for_kafka
}

main "$@"
