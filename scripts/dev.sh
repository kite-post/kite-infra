#!/usr/bin/env bash
# Локальна підміна сервіса (12.6): пише docker-compose.override.yml, у якому
# замість image: з реєстру стоїть build: із сусіднього клону. Решта стенда
# лишається на образах із GHCR. Можна підмінити кілька сервісів по черзі.
#
#   scripts/dev.sh shipment-service              # клон у ../shipment-service
#   scripts/dev.sh shipment-service ~/src/ship   # клон деінде
#   scripts/dev.sh --off                         # повернути всі сервіси на образи
set -euo pipefail

cd "$(dirname "$0")/.."

override="docker-compose.override.yml"

if [ "${1:-}" = "--off" ]; then
  if [ -f "$override" ]; then
    mv "$override" "$override.off"
    echo "Підміну вимкнено (збережено в $override.off)."
  fi
  exit 0
fi

service="${1:-}"
src="${2:-../$service}"

if [ -z "$service" ]; then
  echo "Використання: make dev SERVICE=<сервіс> [SRC=<шлях до клону>]" >&2
  exit 2
fi

known="$(docker compose --profile full --profile obs --profile tools config --services)"
if ! printf '%s\n' "$known" | grep -qx "$service"; then
  echo "Сервіса «$service» немає в stand.yml." >&2
  exit 1
fi

if [ ! -f "$src/Dockerfile" ]; then
  echo "У $src немає Dockerfile. Склонуй репозиторій поруч: gh repo clone kite-post/$service ../$service" >&2
  exit 1
fi
src="$(cd "$src" && pwd)"

# Сервіси, які вже підмінені, зберігаємо: рядок «# dev: <сервіс> <шлях>».
entries=""
if [ -f "$override" ]; then
  entries="$(grep -E '^# dev: ' "$override" | sed 's/^# dev: //' | grep -v "^$service " || true)"
fi
entries="$(printf '%s\n%s %s\n' "$entries" "$service" "$src" | sed '/^$/d')"

# settings.xml із токеном GitHub Packages потрібен Java-збірці, щоб стягнути
# kite-contracts. Передаємо його секретом BuildKit, лише якщо він є.
m2="${M2_SETTINGS:-$HOME/.m2/settings.xml}"

{
  echo "# Згенеровано scripts/dev.sh — не комітити (є в .gitignore)."
  echo "# Вимкнути: make dev-off"
  printf '%s\n' "$entries" | sed 's/^/# dev: /'
  echo "services:"
  printf '%s\n' "$entries" | while read -r name path; do
    echo "  $name:"
    echo "    image: kite-local/$name:dev"
    echo "    pull_policy: build"
    echo "    build:"
    echo "      context: $path"
    if [ -f "$m2" ]; then
      echo "      secrets: [m2settings]"
    fi
    echo "    environment:"
    echo "      KITE_IMAGE_TAG: dev"
  done
  if [ -f "$m2" ]; then
    echo "secrets:"
    echo "  m2settings:"
    echo "    file: $m2"
  fi
} > "$override"

echo "Підмінено з локальних джерел:"
printf '%s\n' "$entries" | sed 's/^/  /'
