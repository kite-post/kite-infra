#!/usr/bin/env bash
# JWT тестового користувача з realm kite — `make token ROLE=operator`.
#
#   scripts/token.sh operator           # access-токен у stdout
#   scripts/token.sh shift_manager -v   # плюс розібраний payload у stderr
#
# Роль пишеться як у 3.1 (OPERATOR, SHIFT_MANAGER) або як логін (shift-manager).
# Персонал входить із TOTP: код рахується зі спільного ключа стенда (README).
# Токен видає kite-dev-cli — єдиний клієнт із password grant, лише для стенда.
set -euo pipefail

role="${1:-}"
verbose="${2:-}"
[ -n "$role" ] || { echo "Вкажи роль: make token ROLE=operator" >&2; exit 2; }

username="$(printf '%s' "$role" | tr '[:upper:]_' '[:lower:]-')"
url="${KEYCLOAK_URL:-http://localhost:8081}/realms/kite/protocol/openid-connect/token"

args=(-d grant_type=password -d client_id=kite-dev-cli -d "username=$username" -d password=kite)
case "$username" in
  operator|sorter|shift-manager|driver|dispatcher|support|admin)
    totp="$(python3 - <<'PY'
import hmac, hashlib, struct, time
key = b"KiteStandTotpSecret1"
h = hmac.new(key, struct.pack(">Q", int(time.time()) // 30), hashlib.sha1).digest()
o = h[-1] & 15
print("%06d" % ((struct.unpack(">I", h[o:o + 4])[0] & 0x7fffffff) % 1000000))
PY
)"
    args+=(-d "totp=$totp")
    ;;
esac

response="$(curl -sS "$url" "${args[@]}")" || { echo "Keycloak недоступний: $url" >&2; exit 1; }

printf '%s' "$response" | python3 -c '
import base64, json, sys
verbose = sys.argv[1] == "-v"
r = json.load(sys.stdin)
if "access_token" not in r:
    sys.exit("Keycloak відмовив: %s" % r.get("error_description", r))
token = r["access_token"]
print(token)
if verbose:
    p = token.split(".")[1]
    p += "=" * (-len(p) % 4)
    print(json.dumps(json.loads(base64.urlsafe_b64decode(p)), ensure_ascii=False, indent=2), file=sys.stderr)
' "$verbose"
