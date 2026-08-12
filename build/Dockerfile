# syntax=docker/dockerfile:1
# Default LaunchPad application image. Models a standard app lifecycle:
#   1 Dependencies -> DEPENDENCY_COMMAND   2+3 Configure/Build -> BUILD_COMMAND
#   4 Install -> this build (COPY + unit)  5 Run -> RUN_COMMAND via app.service
# Requires a buildx named context "launchpad" pointing at this directory
# (for app.service.in), e.g.:
#   docker buildx build -f build/Dockerfile --build-context launchpad=build <repo>
ARG BASE_IMAGE=ghcr.io/mieweb/opensource-server/docker-nodejs:latest
FROM ${BASE_IMAGE}
SHELL ["/bin/bash", "-c"]

ARG WORKING_DIRECTORY=/workspace
ARG DEPENDENCY_COMMAND="npm ci --no-audit --no-fund"
ARG BUILD_COMMAND=""
ARG RUN_COMMAND="npm start"
ARG REPO_URL=""

COPY . ${WORKING_DIRECTORY}
WORKDIR ${WORKING_DIRECTORY}

# -- Lifecycle 1: Dependencies --
RUN eval "$DEPENDENCY_COMMAND"

# -- Lifecycle 2+3: Configure + Build (no-op when empty) --
RUN eval "$BUILD_COMMAND"

# -- Lifecycle 4: Install --
RUN --mount=type=bind,from=launchpad,source=app.service.in,target=/tmp/app.service.in \
    envsubst '${WORKING_DIRECTORY} ${RUN_COMMAND} ${REPO_URL}' \
      </tmp/app.service.in >/etc/systemd/system/app.service \
 && systemctl enable app.service
