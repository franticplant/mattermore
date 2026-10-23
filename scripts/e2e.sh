#!/usr/bin/env bash
#
# Runs a built Mattermore image for real and checks what the docs promise:
# more than 250 users can be created, and the calls plugin that ships in it is
# ours and is running.
#
# Usage: ./scripts/e2e.sh [image]
# Requires: docker.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
engine="${CONTAINER_ENGINE:-docker}"
docker() { command "$engine" "$@"; }

IMAGE="${1:-mattermore:dev}"
USERS="${USERS:-255}"          # the upstream hard limit is 250
RUN="mm-e2e-$$"
PW='Passw0rd1234!'

cleanup() {
    result=$?
    if [ "$result" -ne 0 ]; then docker logs "$RUN-mm" >&2 || true; fi
    docker rm -f "$RUN-mm" "$RUN-db" >/dev/null 2>&1 || true
    docker network rm "$RUN" >/dev/null 2>&1 || true
    for dir in config data logs plugins client-plugins; do docker volume rm "$RUN-$dir" >/dev/null 2>&1 || true; done
}
trap cleanup EXIT

docker network create "$RUN" >/dev/null
docker run -d --name "$RUN-db" --network "$RUN" \
    -e POSTGRES_USER=mmuser -e POSTGRES_PASSWORD=pw -e POSTGRES_DB=mattermost \
    docker.io/library/postgres:17-alpine@sha256:eee6c6e1b0894fa4fe0075eb054af9fd1cf39a35321c2d4110626cfe506411fb >/dev/null
for _ in $(seq 1 30); do
    docker exec "$RUN-db" pg_isready -U mmuser -d mattermost >/dev/null 2>&1 && break; sleep 2
done

test "$(docker image inspect "$IMAGE" --format '{{.Architecture}}')" = amd64
test "$(docker image inspect "$IMAGE" --format '{{.Config.User}}')" = 2000:2000
docker run --rm "$IMAGE" version | tee /dev/stderr | grep -q '12.0.1'
docker run -d --name "$RUN-mm" --network "$RUN" \
    --read-only --cap-drop=ALL --security-opt=no-new-privileges --pids-limit=512 \
    --tmpfs /tmp:rw,mode=1777 --tmpfs /var/tmp:rw,mode=1777 \
    -v "$RUN-config:/mattermost/config" -v "$RUN-data:/mattermost/data" \
    -v "$RUN-logs:/mattermost/logs" -v "$RUN-plugins:/mattermost/plugins" \
    -v "$RUN-client-plugins:/mattermost/client/plugins" \
    -p 127.0.0.1::8065 \
    -e MM_SQLSETTINGS_DRIVERNAME=postgres \
    -e MM_SQLSETTINGS_DATASOURCE="postgres://mmuser:pw@$RUN-db:5432/mattermost?sslmode=disable&connect_timeout=10" \
    -e MM_SERVICESETTINGS_SITEURL=http://localhost:8065 \
    "$IMAGE" >/dev/null

mmctl() { docker exec "$RUN-mm" /mattermost/bin/mmctl --local "$@"; }

echo "==> waiting for the server"
for _ in $(seq 1 60); do mmctl system version >/dev/null 2>&1 && break; sleep 3; done
mmctl system version >/dev/null || { docker logs --tail 40 "$RUN-mm"; echo "server never came up" >&2; exit 1; }
port="$(docker port "$RUN-mm" 8065/tcp | head -1)"
curl --fail --retry 5 --retry-connrefused "http://$port/api/v4/system/ping" | \
    python3 -c 'import json,sys; assert json.load(sys.stdin)["status"] == "OK"'
# No shell/curl dependency is introduced into production images.
tmp="$(mktemp -d)"
docker cp "$RUN-mm:/mattermost/client/root.html" "$tmp/root.html"
docker cp "$RUN-mm:/mattermost/NOTICE-Mattermore-AGPL.txt" "$tmp/NOTICE"
docker cp "$RUN-mm:/mattermost/build-inputs/upstream.env" "$tmp/upstream.env"
cmp "$ROOT/upstream.env" "$tmp/upstream.env"
rm -rf "$tmp"

echo "==> creating $USERS users"
created=0
for i in $(seq 1 "$USERS"); do
    if err="$(mmctl user create --email "e2e$i@example.com" --username "e2e$i" --password "$PW" 2>&1)"; then
        created=$((created + 1))
    else
        echo "user $i refused: $err" >&2; break
    fi
done
[ "$created" -eq "$USERS" ] || { echo "FAIL: only $created of $USERS users created" >&2; exit 1; }

echo "==> checking the calls plugin"
# The output lists enabled plugins first, then disabled ones. The plugin starts
# in the background, so give it a minute rather than racing it.
enabled=""
for _ in $(seq 1 20); do
    enabled="$(mmctl plugin list | awk '/^Listing disabled/ {exit} {print}')"
    grep -q "com.mattermost.calls: Calls (Mattermore)" <<<"$enabled" && break
    sleep 3
done
echo "$enabled"
if ! grep -q "com.mattermost.calls: Calls (Mattermore)" <<<"$enabled"; then
    echo "--- plugin list" >&2; mmctl plugin list >&2 || true
    echo "--- server log, plugin lines" >&2; docker logs "$RUN-mm" 2>&1 | grep -i "plugin\|calls" | tail -40 >&2
    echo "FAIL: Mattermore calls plugin is not enabled" >&2; exit 1
fi

echo "PASS: $created users created, calls plugin enabled"
