#!/usr/bin/env bash
# Статична перевірка стенда — `make test` і CI. Нічого не запускає і не тягне.
#
#  1. compose-конфіг валідний для кожного профілю;
#  2. склад профілів збігається з таблицею 12.1;
#  3. у stand.yml немає build: — стенд тільки тягне образи (12.6);
#  4. versions.env і stand.yml описують ті самі сервіси, а теги закріплені;
#  5. shell-скрипти хоча б парсяться.
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
err() { echo "  ✗ $*"; fail=1; }
ok() { echo "  ✓ $*"; }

services_of() { docker compose "$@" config --services | sort; }

echo "Compose-конфіг"
for profile in core full obs tools; do
  if out="$(docker compose --profile "$profile" config -q 2>&1)"; then
    ok "профіль $profile"
  else
    err "профіль $profile: $out"
  fi
done

echo "Склад профілів (12.1)"
infra="postgres redis kafka kafka-init mosquitto minio minio-init keycloak mailpit tiles"
core_apps="api-gateway customer-service shipment-service pricing-service network-service logistics-service tracking-service payment-service notification-service scan-service realtime-service locker-service mock-pay sms-gateway-emu kite-web kite-ops kite-box-screen"
full_only="business-service care-service audit-service ai-service kite-business photon kafka-ui"
obs="otel-collector prometheus loki tempo grafana"

expect() { printf '%s\n' $1 | sort; }
check_profile() {
  local name="$1" want="$2"
  local got
  got="$(services_of --profile "$name")"
  if [ "$got" = "$(expect "$want")" ]; then
    ok "$name: $(printf '%s\n' "$got" | wc -l | tr -d ' ') сервісів"
  else
    err "$name не збігається з 12.1:"
    diff <(expect "$want") <(printf '%s\n' "$got") | sed 's/^/      /' || true
  fi
}
check_profile core "$infra $core_apps"
check_profile full "$infra $core_apps $full_only"
check_profile obs "$obs"

echo "Лише готові образи"
if grep -nE '^\s+build:' stand.yml docker-compose.yml; then
  err "у compose є build: — збірка з джерел живе лише в docker-compose.override.yml (make dev)"
else
  ok "build: немає"
fi

echo "versions.env"
tag_keys="$(grep -oE '^[A-Z0-9_]+_TAG' versions.env | sort)"
used_keys="$(grep -oE '\$\{[A-Z0-9_]+_TAG' stand.yml | tr -d '${' | sort -u)"
if [ "$tag_keys" = "$used_keys" ]; then
  ok "$(printf '%s\n' "$tag_keys" | wc -l | tr -d ' ') ключів <СЕРВІС>_TAG, усі використані"
else
  err "ключі versions.env і stand.yml розійшлися:"
  diff <(printf '%s\n' "$tag_keys") <(printf '%s\n' "$used_keys") | sed 's/^/      /' || true
fi

# Ключ має виводитися з імені образу так само, як у дії bump-infra-version.
while read -r image key; do
  want="$(printf '%s' "$image" | tr '[:lower:]-' '[:upper:]_')_TAG"
  [ "$want" = "$key" ] || err "образ $image має ключ $key, а bump-infra-version писатиме $want"
done < <(grep -oE '\$\{KITE_REGISTRY\}/[a-z0-9-]+:\$\{[A-Z0-9_]+' stand.yml \
  | sed -E 's|\$\{KITE_REGISTRY\}/([a-z0-9-]+):\$\{([A-Z0-9_]+)|\1 \2|')

bad_tags="$(grep -E '^[A-Z0-9_]+_TAG=' versions.env \
  | grep -vE '=(unreleased|sha-[0-9a-f]{7,40}|v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?)$' || true)"
if [ -n "$bad_tags" ]; then
  err "незакріплені теги: $bad_tags"
else
  ok "теги сервісів закріплені (sha-…, v… або unreleased)"
fi

bad_images="$(grep -E '^[A-Z0-9_]+_IMAGE=' versions.env | grep -E '(:latest$|=[^:]+$)' || true)"
if [ -n "$bad_images" ]; then
  err "сторонні образи без тега або з latest: $bad_images"
else
  ok "сторонні образи закріплені"
fi

echo "Скрипти"
for f in scripts/*.sh config/*/*.sh config/postgres/init/*.sh; do
  if bash -n "$f"; then ok "$f"; else err "$f"; fi
done

if [ "$fail" -ne 0 ]; then
  echo
  echo "Перевірка не пройшла."
  exit 1
fi
echo
echo "Усе гаразд."
