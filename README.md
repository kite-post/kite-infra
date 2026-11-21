# kite-infra

Репозиторій-оркестратор Kite: один compose-стенд із профілями, теги всіх
образів у `versions.env` і команди розробника в `Makefile`. Нічого не збирає —
тягне готові образи з `ghcr.io/kite-post` за закріпленими тегами.

Документація: [12 · Інфраструктура і локальний деплой](https://github.com/kite-post/docs/blob/main/docs/03-arkhitektura/12-infrastruktura-i-lokalnyi-deploi.md).

## Швидкий старт

```bash
make infra       # лише інфраструктура; чекає, поки всі контейнери стануть healthy
make up          # профіль core, ~7 ГБ RAM
make obs         # + Grafana на http://localhost:3300
make smoke       # що з портів 12.2 відповідає
make down        # зупинити, дані лишаються
make down-v      # зупинити й видалити дані
```

Те саме без make: `docker compose --profile core up -d`. Теги з `versions.env`
підставляються самі — `docker-compose.yml` підключає `stand.yml` через
`include` разом з цим файлом, тож `--env-file` не потрібен.

## Профілі (12.1)

| Профіль | Що входить                                                                                                         |
| ------- | ------------------------------------------------------------------------------------------------------------------ |
| `core`  | Postgres, Redis, Kafka, Mosquitto, MinIO, Keycloak, Mailpit, тайли, 14 сервісів MVP, kite-web, kite-ops, kite-box-screen |
| `full`  | core + business, care, audit, ai-service, kite-business, Photon, Kafka UI                                          |
| `obs`   | OpenTelemetry Collector, Prometheus, Loki, Tempo, Grafana                                                          |
| `tools` | разові контейнери для `make seed` і `make tiles`, самі не стартують                                                |

`make test` звіряє склад профілів із таблицею 12.1 — якщо додаєш сервіс,
додай його і в `scripts/check.sh`.

## Команди (12.5)

| Команда                         | Що робить                                                                   |
| ------------------------------- | --------------------------------------------------------------------------- |
| `make infra`                    | Postgres+PostGIS, Redis, Kafka (KRaft), Mosquitto, MinIO з healthcheck, топіки й бакети; повертається, коли все здорове |
| `make up` / `make up-full`      | Підняти core / full; спершу перевіряє, що всі сервіси вже опубліковані      |
| `make obs`                      | Підняти спостережуваність                                                   |
| `make pull [PROFILE=full]`      | Підтягнути образи поточних версій із GHCR                                   |
| `make bump SERVICE=… TAG=…`     | Підняти тег сервіса у `versions.env` (лише `sha-…` або `v…`)               |
| `make dev SERVICE=… [SRC=…]`    | Зібрати сервіс із клону (`../<сервіс>` за замовчуванням), решта — з GHCR    |
| `make dev-off`                  | Повернути всі сервіси на образи                                             |
| `make seed`                     | Перезалити сид-дані (поки заглушка — 12.4 ще попереду)                      |
| `make tiles`                    | Вирізати Україну з Protomaps у `data/tiles/ukraine.pmtiles`                 |
| `make test`                     | Статична перевірка: compose, профілі, `versions.env`, скрипти — те саме в CI |
| `make smoke`                    | Перевірити порти запущеного стенда                                          |
| `make down` / `make down-v`     | Зупинити / зупинити й видалити томи                                         |
| `make logs SERVICE=…`, `make ps` | Логи і стан                                                                 |

> Чому `make down-v`, а не `make down -v`: `-v` make сприймає як власний
> прапорець `--version`, друкує версію і нічого не зупиняє.

## Версії

`versions.env` — єдине місце, яке описує склад стенда:

- `<СЕРВІС>_TAG` — тег нашого образу. Ключ виводиться з імені образу:
  `shipment-service` → `SHIPMENT_SERVICE_TAG`. Ці рядки піднімає PR від
  пайплайна сервіса (дія `bump-infra-version` у `.github`, секрет
  `INFRA_BUMP_TOKEN`); мердж PR = деплой на стенд. На сервіс відкритий один
  PR у гілці `bump/<сервіс>` — нова публікація оновлює його. Рядок міняє
  `scripts/bump.sh`, тож PR і `make bump` поводяться однаково.
- `unreleased` — сервіс ще не публікувався. `make up` назве такі сервіси і
  зупиниться; `FORCE=1` — підняти все одно (compose впаде на їхньому pull).
- `*_IMAGE` — сторонні образи з закріпленим тегом, оновлюються окремим PR.

## Локальна розробка сервіса

```bash
gh repo clone kite-post/shipment-service ../shipment-service
make dev SERVICE=shipment-service
```

`make dev` пише `docker-compose.override.yml` (у `.gitignore`), де замість
`image:` у сервіса стоїть `build:` з клону; compose накладає його сам. Можна
підмінити кілька сервісів по черзі. Для Java-збірки, якій потрібен
`kite-contracts` із GitHub Packages, підхоплюється `~/.m2/settings.xml`
(або `M2_SETTINGS=…`) як секрет BuildKit.

Сервіс можна запускати й з IDE: `make infra` піднімає лише інфраструктуру,
вона доступна з хоста на портах нижче, Kafka — на `localhost:9092`.

У кожного інфраструктурного контейнера є healthcheck, і сервіси стартують
через `depends_on: condition: service_healthy` (12.3); `kafka-init` і
`minio-init` — через `service_completed_successfully`.

## Що отримує сервіс у контейнері

Усі наші сервіси слухають `8080` усередині мережі; на хост виставлені лише
порти з 12.2.

| Мова   | Змінні                                                                                                                           |
| ------ | -------------------------------------------------------------------------------------------------------------------------------- |
| Java   | `SPRING_DATASOURCE_URL/USERNAME/PASSWORD`, `SPRING_KAFKA_BOOTSTRAP_SERVERS`, `SPRING_DATA_REDIS_HOST`, issuer і JWKS Keycloak, OTLP |
| Go     | `PORT`, `DATABASE_URL`, `KAFKA_BROKERS`, `REDIS_ADDR`, `MQTT_URL`, `SERVICE_NAME`                                                 |
| Python | `PORT`, `DATABASE_URL`, `KAFKA_BOOTSTRAP_SERVERS`                                                                                  |
| усі    | `KITE_IMAGE_TAG` (тег із `versions.env`), `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`; S3 — `KITE_S3_*` там, де потрібен   |

Кожен сервіс має власну базу і роль із тим самим іменем (пароль `kite`);
бази створює `config/postgres/init/01-databases.sh` на порожньому томі.

## Доступи

| Що              | Адреса                     | Логін                                                  |
| --------------- | -------------------------- | ------------------------------------------------------ |
| api-gateway     | http://localhost:8080/api/v1 | —                                                    |
| Keycloak        | http://localhost:8081      | `admin` / `admin`; realm `kite`                        |
| Тестові люди    | realm `kite`               | `client`, `operator`, `sorter`, `admin`, … / `kite`; персонал — ще TOTP (нижче) |
| PostgreSQL      | localhost:5432             | `kite` / `kite` (суперкористувач)                       |
| MinIO           | http://localhost:9002      | `kite` / `kitekite`; бакети `labels`, `photos`, `models` |
| Mailpit         | http://localhost:8025      | —                                                      |
| Kafka UI        | http://localhost:8085      | — (full)                                               |
| Grafana         | http://localhost:3300      | анонімний адмін (obs)                                  |

Повна таблиця портів — 12.2.

## Keycloak: realm `kite`

Realm імпортується з `config/keycloak/import/realm-kite.json` під час першого старту
Keycloak (`--import-realm`). Імпорт спрацьовує лише тоді, коли realm ще немає в базі:
щоб застосувати правки у файлі, потрібен `make down-v` і новий старт.

**Тема входу** — `config/keycloak/themes/kite`: `keycloak.v2` (PatternFly 5) плюс
стилі й тексти бренду з розділу 01 — коралові кнопки-«таблетки», Unbounded і Manrope,
знак-ромб, світла й темна тема за налаштуванням системи. Шаблони FreeMarker не
перевизначені, тому оновлення Keycloak тему не ламають. На стенді кеш тем вимкнено:
правка `kite.css` видна після F5, без перезапуску. Шрифти тягнуться з Google Fonts;
без інтернету сторінка працює на системних шрифтах.

**Ролі** — realm roles з тими самими іменами, що `ActorRole` у `kite-contracts` (3.1).
У токені вони лежать у `realm_access.roles`. Дозволи з ролі виводять самі сервіси
(мапа в `kite-contracts`), а скоуп локації — `network.staff_assignment`; у токені їх немає.
Усі токени мають `aud=kite-api` і живуть 5 хв, далі — refresh.

**Клієнти**

| Клієнт             | Тип                         | Для чого                                             |
| ------------------ | --------------------------- | ---------------------------------------------------- |
| `kite-web`         | public, PKCE                | http://localhost:3000; самореєстрація дає `CLIENT`   |
| `kite-business`    | public, PKCE                | http://localhost:3001                                |
| `kite-ops`         | public, PKCE                | http://localhost:3002                                |
| `kite-mobile`      | public, PKCE                | `ua.kite.mobile:/oauth2redirect`, loopback `127.0.0.1` |
| `kite-dev-cli`     | public, password grant      | Лише стенд: `make token`, інтеграційні тести         |
| `kite-box`         | service account, `SYSTEM`   | Пристрої Kite Box                                    |
| `kite-scanner-emu` | service account, `SYSTEM`   | Стаціонарні сканери-заглушки                         |
| `kite-simulator`   | service account, `SYSTEM`   | Симулятор                                            |
| `kite-users-admin` | service account, `realm-management` | Фасад `/ops/users`: лише керування користувачами |

Секрети сервісних акаунтів беруться зі змінних Keycloak (`KITE_BOX_CLIENT_SECRET`
тощо), а без них — значення за замовчуванням `<клієнт>-secret`, наприклад `kite-box-secret`.

**Тестові люди** — пароль усюди `kite`, id фіксовані (`0193a000-0000-7000-8000-0000000000NN`),
тож сид прив'язує до них профілі й `staff_assignment` без запитів до Keycloak.

| Логін                     | Роль                | id (кінець) |
| ------------------------- | ------------------- | ----------- |
| `client`, `client-2`      | CLIENT              | …01, …02    |
| `biz-owner`, `biz-member` | BIZ_OWNER, BIZ_MEMBER | …03, …04  |
| `operator`                | OPERATOR            | …05         |
| `sorter`                  | SORTER              | …06         |
| `shift-manager`           | SHIFT_MANAGER       | …07         |
| `driver`                  | DRIVER              | …08         |
| `dispatcher`              | DISPATCHER          | …09         |
| `support`                 | SUPPORT             | …10         |
| `admin`                   | ADMIN               | …11         |

Персонал (від `operator` до `admin`) входить із TOTP. Ключ спільний для стенда:
`KiteStandTotpSecret1`, для застосунку-автентифікатора — base32
`JNUXIZKTORQW4ZCUN52HAU3FMNZGK5BR` (TOTP, SHA1, 6 цифр, 30 с). На стенді один код
можна використати кілька разів — щоб тести брали токени поспіль.

```bash
make token ROLE=operator        # access-токен у stdout
make token ROLE=shift_manager V=1   # плюс payload у stderr
curl -H "Authorization: Bearer $(make -s token ROLE=client)" http://localhost:8080/api/v1/…
```

Вхід клієнта за кодом із SMS (FR-101) ще не зроблено: поки клієнт входить за паролем.

## Структура

```
docker-compose.yml   точка входу: include stand.yml + versions.env
stand.yml            усі сервіси стенда і профілі
versions.env         теги образів
config/              postgres, kafka, mosquitto, minio, keycloak, tiles, obs
scripts/             bump, dev, tiles, check (make test), smoke, token
seed/                сид-дані (заглушка)
data/tiles/          PMTiles, не в git
```

## Нюанси

- **MinIO.** Офіційних образів MinIO на Docker Hub і quay.io більше немає;
  стенд бере `pgsty/minio` — підтримуваний форк зі збірками для amd64 і arm64.
- **PostGIS.** `imresamu/postgis` — той самий образ, що `postgis/postgis`, але з arm64.
- **Keycloak** видає токени з `iss=http://localhost:8081/realms/kite`, а ключі
  сервіси тягнуть із `keycloak:8080` — тому в Java-сервісах задані і issuer, і JWKS.
- **Photon** (full) на першому старті завантажує індекс України на кілька ГБ.
