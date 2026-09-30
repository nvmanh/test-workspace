#!/bin/sh
# Build the Docker image for this repository.
#
# Usage: scripts/docker-build.sh [TAG]
#        scripts/docker-build.sh -h | --help

set -eu

usage() {
  printf '%s\n' \
    'Usage: scripts/docker-build.sh [TAG]' \
    '       scripts/docker-build.sh -h | --help' \
    '' \
    'Build Docker image <IMAGE_NAME>:<TAG> from the repository root.' \
    '' \
    'Arguments:' \
    '  TAG           Image tag (default: latest)' \
    '' \
    'Environment:' \
    '  IMAGE_NAME    Image name (default: test-workspace)'
}

# 1. Help
case ${1-} in
  -h|--help)
    usage
    exit 0
    ;;
esac

# 2. Too many arguments
if [ $# -gt 1 ]; then
  printf 'Error: too many arguments (expected at most 1, got %d)\n\n' "$#" >&2
  usage >&2
  exit 2
fi

# 3. docker must be on PATH
if ! command -v docker >/dev/null 2>&1; then
  printf "Error: 'docker' command not found in PATH\n" >&2
  exit 127
fi

# 4. Image reference
IMAGE_NAME=${IMAGE_NAME:-test-workspace}
TAG=${1:-latest}

# 5. Repository root, resolved from the script location (no external commands)
case $0 in
  */*) script_dir=${0%/*} ;;
  *)   script_dir=. ;;
esac
REPO_ROOT=$(cd "$script_dir/.." && pwd -P)

# 6. Build; the script's exit status is docker build's exit status
exec docker build -t "$IMAGE_NAME:$TAG" -f "$REPO_ROOT/Dockerfile" "$REPO_ROOT"
