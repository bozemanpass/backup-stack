#!/usr/bin/env bash
# Build bozemanpass/backup
set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# `stack build` provides the target tag (e.g. bozemanpass/backup:stack, or :<cluster>
# when publishing). Fall back to the local :stack tag for a manual build.
TAG="${STACK_DEFAULT_CONTAINER_IMAGE_TAG:-bozemanpass/backup:stack}"

docker build -t "$TAG" ${build_command_args:-} -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR"
