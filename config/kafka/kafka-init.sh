#!/bin/bash
# Топіки стенда (12.3): по PARTITIONS розділів, фактор реплікації 1.
# Список — топіки з events/registry.json у kite-contracts; новий топік у
# реєстрі = новий рядок тут (`make test` звіряє, якщо kite-contracts поруч).
#
# Ідемпотентний: повторний запуск не чіпає наявні топіки, лише добирає
# розділи, якщо топік колись створили з меншою кількістю. Зменшити кількість
# розділів Kafka не вміє — такий топік лишається як є, з попередженням.
set -euo pipefail

BOOTSTRAP="${BOOTSTRAP:-kafka:19092}"
PARTITIONS="${PARTITIONS:-6}"
REPLICATION=1
KT=/opt/kafka/bin/kafka-topics.sh

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

partitions_of() {
  "$KT" --bootstrap-server "$BOOTSTRAP" --describe --topic "$1" 2>/dev/null \
    | sed -nE 's/.*PartitionCount:[[:space:]]*([0-9]+).*/\1/p' | head -n1
}

for topic in "${topics[@]}"; do
  "$KT" --bootstrap-server "$BOOTSTRAP" --create --if-not-exists \
    --topic "$topic" --partitions "$PARTITIONS" --replication-factor "$REPLICATION" >/dev/null

  have="$(partitions_of "$topic")"
  if [ -z "$have" ]; then
    echo "  ✗ $topic: не видно після створення" >&2
    exit 1
  elif [ "$have" -lt "$PARTITIONS" ]; then
    "$KT" --bootstrap-server "$BOOTSTRAP" --alter --topic "$topic" --partitions "$PARTITIONS" >/dev/null
    echo "  ↑ $topic: $have → $PARTITIONS розділів"
  elif [ "$have" -gt "$PARTITIONS" ]; then
    echo "  ! $topic: $have розділів (більше за $PARTITIONS, лишаю як є)"
  else
    echo "  ✓ $topic: $have розділів"
  fi
done

echo "Топіки готові (${#topics[@]})."
