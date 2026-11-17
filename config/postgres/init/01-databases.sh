#!/bin/bash
# Окрема база і власник на кожен сервіс (5.1, 5.3). Пароль у всіх — kite:
# це локальний стенд, не продакшн. Виконується лише на порожньому томі.
set -euo pipefail

databases="keycloak customer business shipment pricing network logistics tracking payment notification care audit scan locker mockpay ai"

for db in $databases; do
  echo "Створюю базу $db"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
CREATE ROLE "$db" LOGIN PASSWORD 'kite';
CREATE DATABASE "$db" OWNER "$db";
SQL
done

# PostGIS потрібен network-service (точки, відстані). Розширення ставить
# суперкористувач, щоб сервісу не потрібні були зайві права.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname network \
  -c 'CREATE EXTENSION IF NOT EXISTS postgis;'
