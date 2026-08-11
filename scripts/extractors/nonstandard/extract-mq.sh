#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../base/java-parser.sh"
source "$SCRIPT_DIR/../base/json-writer.sh"

SERVICE_NAME="${1:-}"
REPO_PATH="${2:-.}"
OUTPUT_DIR="${3:-output/nodes}"

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name> <repo-path> [output-dir]"
    exit 1
fi

OUTPUT_FILE="$OUTPUT_DIR/$SERVICE_NAME/nonstandard-mq.json"
mkdir -p "$(dirname "$OUTPUT_FILE")"

COUNT=0
json_array_init "$OUTPUT_FILE"

detect_topic() {
    local content="$1"
    echo "$content" | grep -oE '"(topics?[^"]*)"' | head -1 | tr -d '"' || \
    echo "$content" | grep -oE '"([a-z_-]*topic[^"]*)"' | head -1 | tr -d '"' || \
    echo "$content" | grep -oE "TOPIC_\w+" | head -1 || \
    echo "$content" | grep -oE '[A-Z_]*(TOPIC|QUEUE)[A-Z_]*' | head -1 || \
    echo "unknown-topic"
}

detect_mq_role() {
    local content="$1"
    if echo "$content" | grep -qi "Consumer\|consume\|subscribe\|receive"; then echo "consumer"
    elif echo "$content" | grep -qi "Producer\|produce\|send\|publish"; then echo "producer"
    else echo "participant"
    fi
}

detect_mq_type() {
    local content="$1"
    if echo "$content" | grep -qi "Kafka\|kafka"; then echo "kafka"
    elif echo "$content" | grep -qi "RabbitMQ\|rabbit\|AmqpTemplate"; then echo "rabbitmq"
    elif echo "$content" | grep -qi "RocketMQ\|rocket"; then echo "rocketmq"
    elif echo "$content" | grep -qi "ActiveMQ\|jms"; then echo "activemq"
    else echo "mq"
    fi
}

while IFS= read -r java_file; do
    REL_PATH="${java_file#$REPO_PATH/}"
    CLASS_NAME=$(extract_class_name "$java_file")

    # Kafka
    if grep -qE "KafkaProducer|KafkaConsumer|KafkaTemplate" "$java_file" 2>/dev/null; then
        MQ_TYPE="kafka"
        while IFS= read -r line_info; do
            [ -z "$line_info" ] && continue
            LN=$(echo "$line_info" | cut -d: -f1)
            CONTENT=$(echo "$line_info" | cut -d: -f2-)
            TOPIC=$(detect_topic "$CONTENT")
            ROLE=$(detect_mq_role "$CONTENT")
            NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.${MQ_TYPE}-${LN}"
            NODE_JSON=$(node_interface_json "$NODE_ID" "${ROLE}" "$SERVICE_NAME" "mq" "$ROLE" "$CLASS_NAME" "$CONTENT" "$REL_PATH:$LN" "" "" "[]")
            json_array_add "$OUTPUT_FILE" "$NODE_JSON" false
            COUNT=$((COUNT + 1))
        done < <(grep -nE "(send|publish|subscribe|poll|consume)\s*\(" "$java_file" 2>/dev/null | head -10 || true)
    fi

    # RabbitMQ
    if grep -qE "rabbitTemplate|RabbitTemplate|AmqpTemplate|Channel" "$java_file" 2>/dev/null; then
        MQ_TYPE="rabbitmq"
        while IFS= read -r line_info; do
            [ -z "$line_info" ] && continue
            LN=$(echo "$line_info" | cut -d: -f1)
            CONTENT=$(echo "$line_info" | cut -d: -f2-)
            TOPIC=$(detect_topic "$CONTENT")
            ROLE=$(detect_mq_role "$CONTENT")
            NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.${MQ_TYPE}-${LN}"
            NODE_JSON=$(node_interface_json "$NODE_ID" "${ROLE}" "$SERVICE_NAME" "mq" "$ROLE" "$CLASS_NAME" "$CONTENT" "$REL_PATH:$LN" "" "" "[]")
            json_array_add "$OUTPUT_FILE" "$NODE_JSON" false
            COUNT=$((COUNT + 1))
        done < <(grep -nE "convertAndSend|receiveAndConvert|basicPublish|basicConsume" "$java_file" 2>/dev/null | head -10 || true)
    fi

    # RocketMQ
    if grep -qE "DefaultMQProducer|DefaultMQPushConsumer|RocketMQTemplate" "$java_file" 2>/dev/null; then
        MQ_TYPE="rocketmq"
        while IFS= read -r line_info; do
            [ -z "$line_info" ] && continue
            LN=$(echo "$line_info" | cut -d: -f1)
            CONTENT=$(echo "$line_info" | cut -d: -f2-)
            TOPIC=$(detect_topic "$CONTENT")
            ROLE=$(detect_mq_role "$CONTENT")
            NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.${MQ_TYPE}-${LN}"
            NODE_JSON=$(node_interface_json "$NODE_ID" "${ROLE}" "$SERVICE_NAME" "mq" "$ROLE" "$CLASS_NAME" "$CONTENT" "$REL_PATH:$LN" "" "" "[]")
            json_array_add "$OUTPUT_FILE" "$NODE_JSON" false
            COUNT=$((COUNT + 1))
        done < <(grep -nE "(send|sendOneway|subscribe|registerMessageListener)\s*\(" "$java_file" 2>/dev/null | head -10 || true)
    fi
done < <(scan_java_files "$REPO_PATH")

json_array_close "$OUTPUT_FILE"
echo "[NONSTD-MQ] $SERVICE_NAME: $COUNT MQ interactions detected"
