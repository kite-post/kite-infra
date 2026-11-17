"""Сид-дані стенда (12.4): мережа, маршрутизація, люди.

Поки що заглушка: ціль `make seed` і контейнер уже на місці, а наповнення
з'явиться разом із network-service і customer-service, коли буде куди писати.
"""

import os
import sys


def main() -> int:
    print("seed: сид-дані ще не реалізовані (12.4) — нічого не роблю.")
    print(f"seed: API {os.environ.get('KITE_API_URL', '—')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
