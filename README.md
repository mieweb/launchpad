# MIEWeb LaunchPad

GitHub Action that deploys Docker/OCI images as LXC containers on an [opensource-server](https://github.com/mieweb/opensource-server) Proxmox cluster via the Container API. It derives a container name from your repository and branch, decides when to create/recreate/delete, and delegates every API call to the reusable composite actions in [mieweb/opensource-server/.github/actions](https://github.com/mieweb/opensource-server/tree/main/.github/actions).

## Prerequisites

- A Docker/OCI image published to a container registry (GHCR, Docker Hub, etc.)
- An API key for the create-a-container server (request one from your site admin)

## Repository Secrets

Add these in **Settings > Secrets and variables > Actions**:

| Secret | Description |
|--------|-------------|
| `API_KEY` | API key for the create-a-container server |
| `API_URL` | Base URL of the create-a-container server |

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `api_key` | Yes | — | Bearer token for authenticating with the Container API |
| `api_url` | Yes | — | Base URL of the create-a-container server |
| `template_name` | No | — | Docker/OCI image reference to deploy (e.g., `ghcr.io/org/app:tag`). When provided and a container already exists, it is deleted and recreated with the new template. When omitted, an existing container is reused as-is. |
| `container_env_vars` | No | — | Environment variables to set inside the container (JSON string, e.g., `'{"NODE_ENV": "production"}'`) |
| `services` | No | — | Services configuration (JSON array string) |
| `site_id` | No | `1` | Site ID for the container management system |

## Supported Workflow Events

| Event | Action |
|-------|--------|
| `push` | Creates or recreates the container for the branch (skipped when the push created the branch — the `create` event handles it) |
| `create` | Creates a container for the new branch |
| `workflow_dispatch` | Creates or recreates the container for the current branch |
| `pull_request` (opened/synchronize/reopened) | Creates or recreates the container for the PR head branch |
| `pull_request` (closed) | Deletes the container |
| `delete` | Deletes the container for the deleted branch |

## Container Naming

Containers are named `<owner>-<repo>-<branch>`, lowercased, with any character outside `[a-z0-9-]` replaced by `-`. Names longer than 63 characters (DNS label limit) are truncated to 54 characters plus a `-` and an 8-character hash of the remainder. Template tags containing `/` are normalized to `-` to match `docker/metadata-action` behavior.

## How It Works

```mermaid
sequenceDiagram
    participant GH as GitHub Workflow
    participant LP as LaunchPad
    participant API as Container API
    participant Prox as Proxmox Cluster

    GH->>LP: push / create / pull_request / delete
    LP->>API: get-container (by hostname)

    alt Manage event (push, create, PR open/sync)
        alt Container exists and template_name provided
            LP->>API: delete-container
            LP->>API: create-container
        else Container exists, no template_name
            LP->>LP: Reuse existing container
        else No container
            LP->>API: create-container
        end
        API->>Prox: Enqueue creation job
        LP->>API: wait-for-job (poll until done)
        LP->>API: get-container (final status)
        LP->>GH: Report name, status, IP, ports, node
    else Delete event (branch delete, PR closed)
        LP->>API: delete-container
    end
```

Each API call is a thin composite action: [get-container](https://github.com/mieweb/opensource-server/tree/main/.github/actions/get-container), [create-container](https://github.com/mieweb/opensource-server/tree/main/.github/actions/create-container), [delete-container](https://github.com/mieweb/opensource-server/tree/main/.github/actions/delete-container), [wait-for-job](https://github.com/mieweb/opensource-server/tree/main/.github/actions/wait-for-job).

The action fails if the container is not found after creation or its final status is not `running`.

## Basic Usage

```yaml
- uses: mieweb/launchpad@main
  with:
    api_key: ${{ secrets.API_KEY }}
    api_url: ${{ secrets.API_URL }}
    template_name: ghcr.io/your-org/your-app:latest
```

## PR Preview Environments

Deploy preview containers on pull requests and clean them up when the PR closes:

```yaml
name: PR Preview

on:
  pull_request:
    types: [opened, synchronize, reopened, closed]

jobs:
  deploy-preview:
    if: github.event.action != 'closed'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: mieweb/launchpad@main
        with:
          api_key: ${{ secrets.API_KEY }}
          api_url: ${{ secrets.API_URL }}
          template_name: ghcr.io/your-org/your-app:pr-${{ github.event.pull_request.number }}

  cleanup-preview:
    if: github.event.action == 'closed'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: mieweb/launchpad@main
        with:
          api_key: ${{ secrets.API_KEY }}
          api_url: ${{ secrets.API_URL }}
```

`template_name` is not needed for cleanup — the closed PR event triggers deletion of the container associated with the PR head branch.

## Complete Example: Build + Deploy

Build an image, push it to GHCR, and deploy a preview container on every PR:

```yaml
name: Build and Deploy Preview

on:
  pull_request:
    types: [opened, synchronize, reopened, closed]

env:
  REGISTRY: ghcr.io

jobs:
  build-and-push:
    if: github.event.action != 'closed'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ${{ env.REGISTRY }}/${{ github.repository }}
          tags: |
            type=ref,event=pr

      - uses: docker/build-push-action@v6
        with:
          push: true
          tags: ${{ steps.meta.outputs.tags }}

  deploy-preview:
    if: github.event.action != 'closed'
    needs: build-and-push
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: mieweb/launchpad@main
        with:
          api_key: ${{ secrets.API_KEY }}
          api_url: ${{ secrets.API_URL }}
          template_name: ${{ env.REGISTRY }}/${{ github.repository }}:pr-${{ github.event.pull_request.number }}

  cleanup-preview:
    if: github.event.action == 'closed'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: mieweb/launchpad@main
        with:
          api_key: ${{ secrets.API_KEY }}
          api_url: ${{ secrets.API_URL }}
```

## Output

After a successful manage run, the workflow log reports the container details:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Container : your-org-your-app-feature-branch
  Status    : running
  IP        : 10.15.129.23
  SSH Port  : 2344
  HTTP Port : 32000
  Node      : opensource-phxdc-pve1
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Misc.
Originally written by [maxklema](https://github.com/maxklema). Rewritten for the Container API by Carter Myers (https://github.com/cmyers-mieweb)).<br>
Feel free to submit a PR/issue here.