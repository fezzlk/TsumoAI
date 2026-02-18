#!/usr/bin/env bash
set -euo pipefail
mkdir -p app/static/tiles
base="https://commons.wikimedia.org/wiki/Special:FilePath"
curl_common=(
  --fail
  --location
  --retry 6
  --retry-delay 1
  --retry-all-errors
  --connect-timeout 10
  --max-time 60
  -A "TsumoAI/0.1"
)
for suit in m p s; do
  for n in 1 2 3 4 5 6 7 8 9; do
    curl "${curl_common[@]}" "$base/Mpu${n}${suit}.png" -o "app/static/tiles/Mpu${n}${suit}.png"
    sleep 0.2
  done
  curl "${curl_common[@]}" "$base/Mpu0${suit}.png" -o "app/static/tiles/Mpu0${suit}.png"
  sleep 0.2
done
for z in 1 2 3 4 5 6 7; do
  curl "${curl_common[@]}" "$base/Mpu${z}z.png" -o "app/static/tiles/Mpu${z}z.png"
  sleep 0.2
done
