#!/usr/bin/env bash
#
# Build the rek.teleport execution environment image.
#
#   1. (Re)build the rek.teleport collection tarball into this directory, so the
#      EE always bundles the current repository source.
#   2. Run ansible-builder to assemble the container image.
#
# Usage:
#   ./build.sh [IMAGE_TAG]
#
# Env vars:
#   CONTAINER_RUNTIME   podman (default) or docker
#
# Examples:
#   ./build.sh
#   ./build.sh quay.io/myorg/rek-teleport-ee:1.0.0
#   CONTAINER_RUNTIME=docker ./build.sh
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTION_DIR="$HERE/../ansible_collections/rek/teleport"
IMAGE_TAG="${1:-rek/teleport-ee:1.0.0}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-podman}"

echo ">> Rebuilding collection tarball from ${COLLECTION_DIR}"
ansible-galaxy collection build "$COLLECTION_DIR" --output-path "$HERE" --force

echo ">> Building execution environment '${IMAGE_TAG}' with ${CONTAINER_RUNTIME}"
ansible-builder build \
  --file "$HERE/execution-environment.yml" \
  --context "$HERE/context" \
  --container-runtime "$CONTAINER_RUNTIME" \
  --tag "$IMAGE_TAG" \
  --verbosity 2

echo ">> Done. Image: ${IMAGE_TAG}"
echo ">> Smoke test:"
echo "     ansible-navigator run ../ansible_collections/rek/teleport/playbooks/site.yml \\"
echo "       --eei ${IMAGE_TAG} -m stdout --syntax-check"
