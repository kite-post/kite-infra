#!/bin/bash
# Топіки стенда (12.3). Список — топіки з events/registry.json у kite-contracts;
# новий топік у реєстрі = новий рядок тут.
set -euo pipefail

BOOTSTRAP="${BOOTSTRAP:-kafka:19092}"
PARTITIONS="${PARTITIONS:-6}"

topics=(
  ai.events
  audit.events
  care.events
  customer.events
  locker.events
  logistics.events
  payment.events
  scan.events
  shipment.events
)

for topic in "${topics[@]}"; do
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" \
    --create --if-not-exists --topic "$topic" \
    --partitions "$PARTITIONS" --replication-factor 1
done

echo "Топіки готові:"
/opt/kafka/bin/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --list
