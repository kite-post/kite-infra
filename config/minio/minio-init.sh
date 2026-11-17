#!/bin/sh
# Бакети MinIO: етикетки PDF, фото (претензії, пошкодження), моделі ai-service.
set -eu

i=0
until mc alias set kite http://minio:9000 kite kitekite >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -ge 60 ]; then
    echo "MinIO не відповів за 60 с" >&2
    exit 1
  fi
  sleep 1
done

for bucket in labels photos models; do
  mc mb --ignore-existing "kite/$bucket"
done
echo "Бакети готові"
