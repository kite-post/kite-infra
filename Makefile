# Команди стенда Kite (12.5). Усе — обгортки над `docker compose`; профілі й
# теги образів описані в stand.yml і versions.env.

COMPOSE ?= docker compose
# Профіль для pull / dev / seed: core, full.
PROFILE ?= core
SERVICE ?=
ROLE    ?=
TAG     ?=
SRC     ?= ../$(SERVICE)
# FORCE=1 — підняти стенд, навіть якщо частина сервісів ще не опублікована.
FORCE   ?=

ALL_PROFILES := --profile full --profile obs --profile tools
# Інфраструктура з healthcheck (12.3, крок 1) і її разові init-контейнери.
INFRA      := postgres redis kafka mosquitto minio
INFRA_INIT := kafka-init minio-init

.DEFAULT_GOAL := help
.PHONY: help infra up up-full obs down down-v pull bump dev dev-off seed token tiles test smoke ps logs released

help: ## Показати цілі
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

infra: ## Лише інфраструктура: Postgres, Redis, Kafka, Mosquitto, MinIO + топіки й бакети
	$(COMPOSE) --profile core up -d --wait $(INFRA)
	@# --wait вважає вихід разового контейнера збоєм навіть із кодом 0, тож
	@# init-контейнери запускаємо окремо і самі перевіряємо їхній код виходу.
	$(COMPOSE) --profile core up --no-log-prefix $(INFRA_INIT)
	@for s in $(INFRA_INIT); do \
		code="$$($(COMPOSE) ps -a --format '{{.ExitCode}}' $$s)"; \
		[ "$$code" = 0 ] || { echo "$$s завершився з кодом $$code" >&2; exit 1; }; \
	done
	@echo "Інфраструктура здорова, топіки й бакети створені."

up: ## Підняти профіль core (~7 ГБ)
	@$(MAKE) --no-print-directory released PROFILE=core
	$(COMPOSE) --profile core up -d

up-full: ## Підняти профіль full (~10 ГБ)
	@$(MAKE) --no-print-directory released PROFILE=full
	$(COMPOSE) --profile full up -d

obs: ## Додати спостережуваність: Grafana на http://localhost:3300
	$(COMPOSE) --profile obs up -d

down: ## Зупинити стенд, дані лишаються в томах
	$(COMPOSE) $(ALL_PROFILES) down --remove-orphans

down-v: ## Зупинити й видалити дані (docker compose down -v)
	$(COMPOSE) $(ALL_PROFILES) down -v --remove-orphans

pull: ## Підтягнути образи поточних версій із GHCR (PROFILE=core|full)
	$(COMPOSE) --profile $(PROFILE) pull --ignore-buildable

bump: ## Підняти версію сервіса у versions.env: SERVICE=… TAG=…
	@scripts/bump.sh "$(SERVICE)" "$(TAG)"

dev: ## Зібрати SERVICE=… з локального клону (SRC=…), решта — з GHCR
	@test -n "$(SERVICE)" || { echo "Вкажи сервіс: make dev SERVICE=shipment-service" >&2; exit 2; }
	@scripts/dev.sh "$(SERVICE)" "$(SRC)"
	@$(MAKE) --no-print-directory released
	$(COMPOSE) --profile $(PROFILE) up -d --build

dev-off: ## Повернути всі сервіси на образи з versions.env
	@scripts/dev.sh --off
	$(COMPOSE) --profile $(PROFILE) up -d

seed: ## Перезалити сид-дані
	$(COMPOSE) --profile $(PROFILE) run --rm seed

token: ## JWT тестового користувача: ROLE=operator (V=1 — показати payload)
	@scripts/token.sh "$(ROLE)" $(if $(V),-v)

tiles: ## Завантажити й обрізати тайли України → data/tiles
	@scripts/tiles.sh

test: ## Статична перевірка: compose, профілі, versions.env, скрипти
	@scripts/check.sh

smoke: ## Перевірити порти запущеного стенда
	@scripts/smoke.sh

ps: ## Стан контейнерів
	$(COMPOSE) ps

logs: ## Логи: make logs SERVICE=shipment-service
	$(COMPOSE) $(ALL_PROFILES) logs -f --tail=200 $(SERVICE)

# Сервіси з тегом unreleased ще жодного разу не публікувались — compose
# упаде на pull. Кажемо про це заздалегідь і по-людськи.
released:
	@missing="$$($(COMPOSE) --profile $(PROFILE) config --images | grep ':unreleased$$' | sed -E 's|.*/([^:]+):.*|\1|' || true)"; \
	if [ -n "$$missing" ] && [ -z "$(FORCE)" ]; then \
		echo "Ще не опубліковані в GHCR (тег unreleased у versions.env):"; \
		printf '  %s\n' $$missing; \
		echo "Підміни їх локальною збіркою (make dev SERVICE=…) або запусти з FORCE=1."; \
		exit 1; \
	fi
