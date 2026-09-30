#!/usr/bin/env bash
# Build SupoClip images locally and push them to GitHub Container Registry, so
# the server (Dokploy) only pulls prebuilt images via docker-compose.prod.yml.
#
# Usage: scripts/ghcr-publish.sh [backend] [frontend] [mcp]   (default: all)
#
# Requires `docker login ghcr.io` with a token that has write:packages.
# Frontend NEXT_PUBLIC_* values are inlined at build time, so they are read
# from .env.build (copy .env.build.example).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ENV_FILE="${ENV_FILE:-$ROOT/.env.build}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

REGISTRY="${REGISTRY:-ghcr.io}"
OWNER="$(echo "${GHCR_OWNER:-elvis-wdev}" | tr '[:upper:]' '[:lower:]')"
PLATFORM="${PLATFORM:-linux/amd64}"
REVISION="$(git rev-parse HEAD)"
TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"
if [[ -z "${IMAGE_TAG:-}" && -n "$(git status --porcelain -- backend frontend mcp)" ]]; then
  echo "warning: working tree has uncommitted changes; tagging as $TAG-dirty" >&2
  TAG="$TAG-dirty"
fi

build() {
  local name="$1" context="$2"
  shift 2
  local image="$REGISTRY/$OWNER/supoclip-$name"
  echo "==> Building and pushing $image:$TAG (+ latest)"
  docker buildx build \
    --platform "$PLATFORM" \
    --tag "$image:$TAG" \
    --tag "$image:latest" \
    --label "org.opencontainers.image.source=https://github.com/$OWNER/supoclip" \
    --label "org.opencontainers.image.revision=$REVISION" \
    --push \
    "$@" \
    "$context"
}

build_backend() {
  # Backend API and ARQ worker share this image.
  build backend backend
}

build_frontend() {
  build frontend frontend \
    --target runner \
    --build-arg NEXT_PUBLIC_API_URL="${NEXT_PUBLIC_API_URL:?set NEXT_PUBLIC_API_URL in .env.build}" \
    --build-arg NEXT_PUBLIC_APP_URL="${NEXT_PUBLIC_APP_URL:?set NEXT_PUBLIC_APP_URL in .env.build}" \
    --build-arg NEXT_PUBLIC_SELF_HOST="${NEXT_PUBLIC_SELF_HOST:-true}" \
    --build-arg NEXT_PUBLIC_PRO_PRICE_MONTHLY="${NEXT_PUBLIC_PRO_PRICE_MONTHLY:-10}" \
    --build-arg NEXT_PUBLIC_SCALE_PRICE_MONTHLY="${NEXT_PUBLIC_SCALE_PRICE_MONTHLY:-50}" \
    --build-arg NEXT_PUBLIC_FREE_PLAN_TASK_LIMIT="${NEXT_PUBLIC_FREE_PLAN_TASK_LIMIT:-10}" \
    --build-arg NEXT_PUBLIC_PRO_PLAN_TASK_LIMIT="${NEXT_PUBLIC_PRO_PLAN_TASK_LIMIT:-50}" \
    --build-arg NEXT_PUBLIC_SCALE_PLAN_TASK_LIMIT="${NEXT_PUBLIC_SCALE_PLAN_TASK_LIMIT:-300}" \
    --build-arg NEXT_PUBLIC_DATAFAST_WEBSITE_ID="${NEXT_PUBLIC_DATAFAST_WEBSITE_ID:-}" \
    --build-arg NEXT_PUBLIC_DATAFAST_DOMAIN="${NEXT_PUBLIC_DATAFAST_DOMAIN:-}" \
    --build-arg NEXT_PUBLIC_DATAFAST_ALLOW_LOCALHOST="${NEXT_PUBLIC_DATAFAST_ALLOW_LOCALHOST:-false}"
}

build_mcp() {
  build mcp mcp
}

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
  targets=(backend frontend mcp)
fi

for target in "${targets[@]}"; do
  case "$target" in
    backend | frontend | mcp) "build_$target" ;;
    *)
      echo "unknown target: $target (expected backend, frontend or mcp)" >&2
      exit 1
      ;;
  esac
done

echo "Done. Deploy with IMAGE_TAG=$TAG (or latest)."
