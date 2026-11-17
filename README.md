# kite-infra

Репозиторій-оркестратор Kite: один compose-стенд із профілями, теги всіх
образів у `versions.env` і команди розробника в `Makefile`. Нічого не збирає —
тягне готові образи з `ghcr.io/kite-post` за закріпленими тегами.

Документація: [12 · Інфраструктура і локальний деплой](https://github.com/kite-post/docs/blob/main/docs/03-arkhitektura/12-infrastruktura-i-lokalnyi-deploi.md).

## Швидкий старт

```bash
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
  `INFRA_BUMP_TOKEN`); мердж PR = деплой на стенд.
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

Сервіс можна запускати й з IDE: інфраструктура доступна з хоста на портах
нижче, Kafka — на `localhost:9092`.

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
| Тестові люди    | realm `kite`               | `client`, `operator`, `sorter`, `admin`, … / `kite`     |
| PostgreSQL      | localhost:5432             | `kite` / `kite` (суперкористувач)                       |
| MinIO           | http://localhost:9002      | `kite` / `kitekite`; бакети `labels`, `photos`, `models` |
| Mailpit         | http://localhost:8025      | —                                                      |
| Kafka UI        | http://localhost:8085      | — (full)                                               |
| Grafana         | http://localhost:3300      | анонімний адмін (obs)                                  |

Повна таблиця портів — 12.2. Тестовий користувач є на кожну роль із 03
(`biz-owner`, `shift-manager` тощо), пароль усюди `kite`.

## Структура

```
docker-compose.yml   точка входу: include stand.yml + versions.env
stand.yml            усі сервіси стенда і профілі
versions.env         теги образів
config/              postgres, kafka, mosquitto, minio, keycloak, tiles, obs
scripts/             bump, dev, tiles, check (make test), smoke
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
