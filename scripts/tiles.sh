#!/usr/bin/env bash
# Вирізка України з планетарної збірки Protomaps у data/tiles/ukraine.pmtiles
# (12.4). pmtiles читає лише потрібні шматки планети запитами Range, тож
# качається кілька сотень МБ, а не весь файл.
#
#   scripts/tiles.sh                  # найсвіжіша збірка
#   TILES_BUILD=20261110 scripts/tiles.sh
set -euo pipefail

cd "$(dirname "$0")/.."

# Прямокутник довкола України: захід, південь, схід, північ.
BBOX="${TILES_BBOX:-22.08,44.18,40.25,52.40}"
MAXZOOM="${TILES_MAXZOOM:-14}"
OUT="data/tiles/ukraine.pmtiles"

build="${TILES_BUILD:-}"
if [ -z "$build" ]; then
  build="$(curl -fsSL https://build-metadata.protomaps.dev/builds.json \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)[-1]["key"].removesuffix(".pmtiles"))')"
fi

url="https://build.protomaps.com/${build}.pmtiles"
echo "Збірка Protomaps: $build"
echo "Вирізаю $BBOX (до z$MAXZOOM) → $OUT"

mkdir -p data/tiles
docker compose --profile tools run --rm pmtiles \
  extract "$url" "/out/ukraine.pmtiles.tmp" --bbox="$BBOX" --maxzoom="$MAXZOOM"
mv -f "data/tiles/ukraine.pmtiles.tmp" "$OUT"

echo "Готово: http://localhost:8090/ukraine.pmtiles"
