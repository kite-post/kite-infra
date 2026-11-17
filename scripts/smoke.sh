#!/usr/bin/env bash
# Димова перевірка запущеного стенда: чи відповідають порти з 12.2.
# Перевіряє лише те, що зараз запущено, — решту пропускає.
set -euo pipefail

cd "$(dirname "$0")/.."

running="$(docker compose ps --status running --services 2>/dev/null || true)"
fail=0

probe() {
  local service="$1" url="$2"
  if ! printf '%s\n' "$running" | grep -qx "$service"; then
    printf '  –  %-22s не запущено\n' "$service"
    return
  fi
  if curl -fsS -o /dev/null --max-time 5 "$url"; then
    printf '  ✓  %-22s %s\n' "$service" "$url"
  else
    printf '  ✗  %-22s %s\n' "$service" "$url"
    fail=1
  fi
}

echo "Стан контейнерів"
docker compose ps --format 'table {{.Service}}\t{{.Status}}'
echo
echo "HTTP"
probe api-gateway      http://localhost:8080/actuator/health
probe keycloak         http://localhost:8081/realms/kite/.well-known/openid-configuration
probe kite-web         http://localhost:3000/healthz
probe kite-business    http://localhost:3001/healthz
probe kite-ops         http://localhost:3002/healthz
probe kite-box-screen  http://localhost:3003/healthz
probe tiles            http://localhost:8090/healthz
probe photon           "http://localhost:2322/api?q=Київ&limit=1"
probe kafka-ui         http://localhost:8085/
probe minio            http://localhost:9000/minio/health/live
probe mailpit          http://localhost:8025/livez
probe mock-pay         http://localhost:8087/healthz
probe sms-gateway-emu  http://localhost:8088/healthz
probe grafana          http://localhost:3300/api/health

unhealthy="$(docker compose ps --format '{{.Service}} {{.Status}}' | grep -E 'unhealthy|Restarting' || true)"
if [ -n "$unhealthy" ]; then
  echo
  echo "Нездорові контейнери:"
  printf '%s\n' "$unhealthy" | sed 's/^/  /'
  fail=1
fi

exit "$fail"
