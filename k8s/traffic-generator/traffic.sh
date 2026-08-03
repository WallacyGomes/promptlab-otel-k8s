#!/bin/sh
set -eu

interval="${INTERVAL_SECONDS:-5}"

wait_for_service() {
  name="$1"
  base_url="$2"
  until curl --silent --fail --max-time 3 "${base_url}/health" >/dev/null; do
    printf 'waiting service=%s url=%s\n' "$name" "$base_url"
    sleep "$interval"
  done
}

make_request() {
  service="$1"
  base_url="$2"
  path="$3"
  expected_status="$4"
  result="$(curl --silent --show-error --output /dev/null \
    --write-out '%{http_code} %{time_total}' \
    --max-time 10 "${base_url}${path}" 2>&1)" || result="000 0"
  actual_status="${result%% *}"
  duration="${result#* }"
  outcome="match"
  if [ "$actual_status" != "$expected_status" ]; then
    outcome="mismatch"
  fi
  printf 'traffic_request service=%s path=%s expectedStatus=%s actualStatus=%s durationSeconds=%s outcome=%s\n' \
    "$service" "$path" "$expected_status" "$actual_status" "$duration" "$outcome"
}

wait_for_service "store-node" "http://store-node:3000"
wait_for_service "catalog-java" "http://catalog-java:8080"
wait_for_service "insights-python" "http://insights-python:8000"

while true; do
  step=1
  while [ "$step" -le 20 ]; do
    case "$step" in
      5|10|15) expected_status="400" ;;
      20) expected_status="500" ;;
      *) expected_status="200" ;;
    esac

    for service in store-node catalog-java insights-python; do
      modulo=$((step % 4))
      case "$service" in
        store-node)
          base_url="http://store-node:3000"
          case "$modulo" in
            0) path="/health" ;;
            1) path="/api/bootstrap" ;;
            2) path="/api/prompts" ;;
            3) path="/api/prompts?categoryId=1" ;;
          esac
          ;;
        catalog-java)
          base_url="http://catalog-java:8080"
          case "$modulo" in
            0) path="/health" ;;
            1) path="/categories" ;;
            2) path="/prompts" ;;
            3) path="/prompts/1" ;;
          esac
          ;;
        insights-python)
          base_url="http://insights-python:8000"
          case "$modulo" in
            0) path="/health" ;;
            1) path="/recommendations?promptId=1" ;;
            2) path="/recommendations/category/1" ;;
            3) path="/stats/popular" ;;
          esac
          ;;
      esac

      if [ "$expected_status" != "200" ]; then
        path="/lab/status/${expected_status}"
      fi

      make_request "$service" "$base_url" "$path" "$expected_status"
      sleep "$interval"
    done

    step=$((step + 1))
  done
done
