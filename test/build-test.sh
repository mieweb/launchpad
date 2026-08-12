#!/usr/bin/env bash
# Builds the default LaunchPad Dockerfile against the fixture app and asserts
# the image contains a correctly rendered, enabled app.service unit.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_URL=https://github.com/mieweb/launchpad

# ── Scenario 1: all defaults ──
docker buildx build \
  --load \
  -f build/Dockerfile \
  --build-context launchpad=build \
  --build-arg REPO_URL="$REPO_URL" \
  -t launchpad-build-test:default \
  test/fixture

unit=$(docker run --rm --entrypoint cat launchpad-build-test:default /etc/systemd/system/app.service)
echo "$unit"
echo "$unit" | grep -Fxq "WorkingDirectory=/workspace"
echo "$unit" | grep -Fxq "ExecStart=/bin/bash -c 'npm start'"
echo "$unit" | grep -Fxq "Documentation=$REPO_URL"

docker run --rm --entrypoint test launchpad-build-test:default -L /etc/systemd/system/multi-user.target.wants/app.service
docker run --rm --entrypoint test launchpad-build-test:default -f /workspace/package.json
docker run --rm --entrypoint test launchpad-build-test:default -f /workspace/server.js

# ── Scenario 2: overridden build_command and run_command ──
docker buildx build \
  --load \
  -f build/Dockerfile \
  --build-context launchpad=build \
  --build-arg REPO_URL="$REPO_URL" \
  --build-arg BUILD_COMMAND='echo built >built.txt' \
  --build-arg RUN_COMMAND='node server.js --port $PORT' \
  -t launchpad-build-test:custom \
  test/fixture

docker run --rm --entrypoint test launchpad-build-test:custom -f /workspace/built.txt

unit2=$(docker run --rm --entrypoint cat launchpad-build-test:custom /etc/systemd/system/app.service)
echo "$unit2"
# envsubst must substitute only the listed variables: $PORT survives verbatim.
echo "$unit2" | grep -Fxq "ExecStart=/bin/bash -c 'node server.js --port \$PORT'"

echo "PASS: build test succeeded"
