#!/bin/sh
# Test suite for the Docker build feature.
#
# Usage: sh tests/docker-build.test.sh   (from any directory)
#
# Groups:
#   1. Static checks          - read files only, always run.
#   2. Build script (stub)    - fake `docker` on PATH, no daemon needed.
#   3. Docker integration     - needs a running Docker daemon. Without one the
#                               group FAILs, unless ALLOW_SKIP_DOCKER=1 (SKIP).
#
# Exits non-zero if any test case fails.

set -u

case $0 in
  */*) TEST_DIR=${0%/*} ;;
  *)   TEST_DIR=. ;;
esac
REPO_ROOT=$(cd "$TEST_DIR/.." && pwd -P)

IMAGE=test-workspace:latest
# Temporary image tags must start with "test-" so cleanup can find them.
TMP_IMAGE_REPO=test-workspace

FAILURES=0
PASSES=0
SKIPS=0
TMP_DIRS=
TMP_IMAGES=

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

pass() {
  PASSES=$((PASSES + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  FAILURES=$((FAILURES + 1))
  printf 'FAIL: %s\n' "$1"
  if [ $# -gt 1 ]; then
    printf '      %s\n' "$2"
  fi
}

skip() {
  SKIPS=$((SKIPS + 1))
  printf 'SKIP: %s\n' "$1"
}

section() {
  printf '\n== %s ==\n' "$1"
}

# assert_success NAME CMD...  - CMD exits 0
assert_success() {
  name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name" "command failed (exit $?): $*"
  fi
}

# assert_failure NAME CMD...  - CMD exits non-zero
assert_failure() {
  name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$name" "command unexpectedly succeeded: $*"
  else
    pass "$name"
  fi
}

# assert_eq NAME EXPECTED ACTUAL
assert_eq() {
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail "$1" "expected '$2', got '$3'"
  fi
}

# assert_ne NAME UNEXPECTED ACTUAL
assert_ne() {
  if [ "$2" != "$3" ]; then
    pass "$1"
  else
    fail "$1" "did not expect '$3'"
  fi
}

# assert_file_has_line NAME FILE LINE  - FILE contains LINE exactly
assert_file_has_line() {
  if [ -f "$2" ] && grep -qxF -- "$3" "$2"; then
    pass "$1"
  else
    fail "$1" "'$2' has no line '$3'"
  fi
}

# assert_file_contains NAME FILE TEXT  - FILE contains TEXT
assert_file_contains() {
  if [ -f "$2" ] && grep -qF -- "$3" "$2"; then
    pass "$1"
  else
    fail "$1" "'$2' does not contain '$3'"
  fi
}

# make_tmp_dir  - sets TMP_DIR to a new temp dir, removed on exit
# (not used via $(...) so the registration survives outside a subshell)
make_tmp_dir() {
  TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/docker-build-test.XXXXXX") || return 1
  TMP_DIRS="$TMP_DIRS $TMP_DIR"
}

# tmp_image SUFFIX  - sets TMP_IMAGE to a temporary image reference, removed on exit
tmp_image() {
  TMP_IMAGE="$TMP_IMAGE_REPO:test-$1"
  TMP_IMAGES="$TMP_IMAGES $TMP_IMAGE"
}

cleanup() {
  for ref in $TMP_IMAGES; do
    docker image rm -f "$ref" >/dev/null 2>&1 || :
  done
  for d in $TMP_DIRS; do
    rm -rf "$d"
  done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---------------------------------------------------------------------------
# 1. Static checks
# ---------------------------------------------------------------------------

run_static_tests() {
  section "Static checks"

  # 1.2: FROM has an explicit tag that is not :latest
  from_line=$(grep -iE '^[[:space:]]*FROM[[:space:]]' "$REPO_ROOT/Dockerfile" 2>/dev/null | head -n 1)
  from_image=$(printf '%s\n' "$from_line" | awk '{print $2}')
  case $from_image in
    "")        fail "1.2 Dockerfile has a FROM line" ;;
    *:latest)  fail "1.2 FROM base image is not tagged latest" "got '$from_image'" ;;
    *:*)       pass "1.2 FROM base image has a pinned tag ($from_image)" ;;
    *)         fail "1.2 FROM base image has an explicit tag" "got '$from_image'" ;;
  esac

  # 3.4: .dockerignore lists .git, .kiro, .env
  for entry in .git .kiro .env; do
    assert_file_has_line "3.4 .dockerignore contains '$entry'" "$REPO_ROOT/.dockerignore" "$entry"
  done

  # 5.1: README has a Markdown heading containing "Docker"
  if grep -qE '^#{1,6}[[:space:]].*Docker' "$REPO_ROOT/README.md" 2>/dev/null; then
    pass "5.1 README.md has a heading containing 'Docker'"
  else
    fail "5.1 README.md has a heading containing 'Docker'"
  fi

  # 5.2: README shows docker build, docker run and the build script
  for text in "docker build" "docker run" "scripts/docker-build.sh"; do
    assert_file_contains "5.2 README.md contains '$text'" "$REPO_ROOT/README.md" "$text"
  done
}

# ---------------------------------------------------------------------------
# 2. Build script with a stub docker (no daemon needed)
# ---------------------------------------------------------------------------

run_stub_tests() {
  section "Build script (stub docker)"
  # Test cases for scripts/docker-build.sh are added here.
  :
}

# ---------------------------------------------------------------------------
# 3. Integration with a real Docker daemon
# ---------------------------------------------------------------------------

docker_available() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

run_integration_tests() {
  section "Docker integration"

  if ! docker_available; then
    if [ "${ALLOW_SKIP_DOCKER:-0}" = 1 ]; then
      skip "Docker integration tests (no Docker daemon, ALLOW_SKIP_DOCKER=1)"
    else
      fail "Docker integration tests require a running Docker daemon" \
        "start Docker or set ALLOW_SKIP_DOCKER=1 to skip"
    fi
    return
  fi

  # 1.1: docker build at the repository root
  if (cd "$REPO_ROOT" && docker build -q -t "$IMAGE" . >/dev/null); then
    pass "1.1 docker build -t $IMAGE . exits 0"
  else
    fail "1.1 docker build -t $IMAGE . exits 0"
    return
  fi
  assert_success "1.1 docker image inspect $IMAGE succeeds" docker image inspect "$IMAGE"

  # 1.3: WORKDIR
  workdir=$(docker image inspect -f '{{.Config.WorkingDir}}' "$IMAGE" 2>/dev/null)
  assert_eq "1.3 Config.WorkingDir is /app" "/app" "$workdir"

  # 1.4: OCI title label
  title=$(docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.title"}}' "$IMAGE" 2>/dev/null)
  assert_eq "1.4 label org.opencontainers.image.title is test-workspace" "test-workspace" "$title"

  # 1.5: broken Dockerfiles fail to build
  make_tmp_dir || { fail "1.5 create temp dir"; return; }
  bad_dir=$TMP_DIR
  printf 'FROMM alpine:3.20\n' > "$bad_dir/Dockerfile.syntax"
  printf 'FROM alpine:3.20\nRUN exit 1\n' > "$bad_dir/Dockerfile.failstep"
  tmp_image syntax
  assert_failure "1.5 docker build fails on a syntax error (FROMM)" \
    docker build -q -t "$TMP_IMAGE" -f "$bad_dir/Dockerfile.syntax" "$bad_dir"
  tmp_image failstep
  assert_failure "1.5 docker build fails when a step fails (RUN exit 1)" \
    docker build -q -t "$TMP_IMAGE" -f "$bad_dir/Dockerfile.failstep" "$bad_dir"

  # 2.1: default command
  assert_success "2.1 docker run --rm $IMAGE exits 0" docker run --rm "$IMAGE"

  # 2.2: non-root user
  uid=$(docker run --rm "$IMAGE" id -u 2>/dev/null)
  if [ -n "$uid" ]; then
    assert_ne "2.2 container runs as non-root (id -u = $uid)" "0" "$uid"
  else
    fail "2.2 container runs as non-root" "could not read id -u"
  fi

  # 2.3: README.md is present
  assert_success "2.3 /app/README.md exists" docker run --rm "$IMAGE" test -f /app/README.md

  # 3.1, 3.2: excluded directories
  assert_success "3.1 /app/.git is absent" docker run --rm "$IMAGE" test ! -e /app/.git
  assert_success "3.2 /app/.kiro is absent" docker run --rm "$IMAGE" test ! -e /app/.kiro

  # 3.3: .env is excluded (built from a copy so the real workspace is untouched)
  make_tmp_dir || { fail "3.3 create temp dir"; return; }
  env_dir=$TMP_DIR
  for f in Dockerfile .dockerignore README.md scripts tests; do
    if [ -e "$REPO_ROOT/$f" ]; then
      cp -R "$REPO_ROOT/$f" "$env_dir/"
    fi
  done
  printf 'SECRET=dummy\n' > "$env_dir/.env"
  tmp_image env
  env_image=$TMP_IMAGE
  if docker build -q -t "$env_image" "$env_dir" >/dev/null 2>&1; then
    assert_success "3.3 /app/.env is absent when the context has .env" \
      docker run --rm "$env_image" test ! -e /app/.env
  else
    fail "3.3 build context with .env builds successfully"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

run_static_tests
run_stub_tests
run_integration_tests

printf '\n%d passed, %d failed, %d skipped\n' "$PASSES" "$FAILURES" "$SKIPS"
[ "$FAILURES" -eq 0 ]
