#!/usr/bin/env bash
# Підняти тег одного сервіса у versions.env — те саме, що робить PR від
# пайплайна сервіса (дія bump-infra-version у .github), лише руками.
#
#   scripts/bump.sh shipment-service sha-1a2b3c4
#   scripts/bump.sh shipment-service v1.2.0
set -euo pipefail

cd "$(dirname "$0")/.."

service="${1:-}"
tag="${2:-}"
file="${VERSIONS_FILE:-versions.env}"

if [ -z "$service" ] || [ -z "$tag" ]; then
  echo "Використання: make bump SERVICE=<сервіс> TAG=<sha-…|v…>" >&2
  exit 2
fi

# Лише закріплені теги з пайплайна: sha-<хеш> або v<semver> (12.6).
if ! printf '%s' "$tag" | grep -Eq '^(sha-[0-9a-f]{7,40}|v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?)$'; then
  echo "Тег «$tag» не схожий на sha-<хеш> або v<semver>. latest і dev сюди не пишемо." >&2
  exit 2
fi

# Ключ: shipment-service -> SHIPMENT_SERVICE_TAG (як у дії bump-infra-version).
key="$(printf '%s' "$service" | tr '[:lower:]-' '[:upper:]_')_TAG"

if ! grep -Eq "^${key}=" "$file"; then
  echo "У $file немає $key. Новий сервіс додається в stand.yml і versions.env одним PR." >&2
  exit 1
fi

current="$(grep -E "^${key}=" "$file" | head -1 | cut -d= -f2-)"
if [ "$current" = "$tag" ]; then
  echo "$key уже дорівнює $tag"
  exit 0
fi

tmp="$(mktemp)"
awk -v k="$key" -v v="$tag" 'BEGIN { FS = OFS = "=" } $1 == k { print k, v; next } { print }' "$file" > "$tmp"
cat "$tmp" > "$file"
rm -f "$tmp"

echo "$key: $current → $tag"
echo "Далі: make pull && make up   (або закомітити versions.env і відкрити PR)"
