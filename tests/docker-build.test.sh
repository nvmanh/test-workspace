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
BUILD_SCRIPT=$REPO_ROOT/scripts/docker-build.sh
SH=$(command -v sh)

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

  # Shell syntax (stands in for type checking)
  for f in scripts/docker-build.sh tests/docker-build.test.sh; do
    assert_success "sh -n $f" sh -n "$REPO_ROOT/$f"
  done

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

# make_stub  - sets STUB_DIR to a temp dir holding a fake `docker` and
# STUB_LOG to its log. The stub writes "ARG: <arg>" per argument to the log
# and exits with $STUB_EXIT (default 0).
make_stub() {
  make_tmp_dir || return 1
  STUB_DIR=$TMP_DIR
  STUB_LOG=$STUB_DIR/docker.log
  : > "$STUB_LOG"
  cat > "$STUB_DIR/docker" <<STUB
#!/bin/sh
for a in "\$@"; do
  printf 'ARG: %s\n' "\$a" >> '$STUB_LOG'
done
exit \${STUB_EXIT:-0}
STUB
  chmod +x "$STUB_DIR/docker"
}

# stub_args  - print the arguments the stub received, one per line
stub_args() {
  sed -n 's/^ARG: //p' "$STUB_LOG"
}

# stub_has_pair NAME FLAG VALUE  - stub received FLAG immediately followed by VALUE
stub_has_pair() {
  if stub_args | awk -v f="$2" -v v="$3" 'p && $0 == v { found = 1 } { p = ($0 == f) } END { exit !found }'; then
    pass "$1"
  else
    fail "$1" "docker was not called with '$2 $3' (log: $(stub_args | tr '\n' ' '))"
  fi
}

run_stub_tests() {
  section "Build script (stub docker)"

  if [ ! -x "$BUILD_SCRIPT" ]; then
    fail "scripts/docker-build.sh exists and is executable"
    return
  fi
  pass "scripts/docker-build.sh exists and is executable"

  make_stub || { fail "create stub docker"; return; }
  stub_path="$STUB_DIR:$PATH"

  # 4.1: no arguments -> test-workspace:latest
  : > "$STUB_LOG"
  PATH=$stub_path "$BUILD_SCRIPT" >/dev/null 2>&1
  assert_eq "4.1 no arguments exits 0" 0 $?
  assert_eq "4.1 docker subcommand is build" build "$(stub_args | head -n 1)"
  stub_has_pair "4.1 docker called with '-t test-workspace:latest'" -t test-workspace:latest

  # 4.2: tag argument
  : > "$STUB_LOG"
  PATH=$stub_path "$BUILD_SCRIPT" 1.0.0 >/dev/null 2>&1
  assert_eq "4.2 tag 1.0.0 exits 0" 0 $?
  stub_has_pair "4.2 docker called with '-t test-workspace:1.0.0'" -t test-workspace:1.0.0

  # 4.3: IMAGE_NAME overrides the image name
  : > "$STUB_LOG"
  PATH=$stub_path IMAGE_NAME=my-image "$BUILD_SCRIPT" 1.0.0 >/dev/null 2>&1
  assert_eq "4.3 IMAGE_NAME=my-image exits 0" 0 $?
  stub_has_pair "4.3 docker called with '-t my-image:1.0.0'" -t my-image:1.0.0

  # 4.4: run from another directory -> context and -f point at the repo root
  make_tmp_dir || { fail "4.4 create temp dir"; return; }
  : > "$STUB_LOG"
  (cd "$TMP_DIR" && PATH=$stub_path "$BUILD_SCRIPT" >/dev/null 2>&1)
  assert_eq "4.4 run from another directory exits 0" 0 $?
  assert_eq "4.4 build context is the repository root" "$REPO_ROOT" "$(stub_args | tail -n 1)"
  stub_has_pair "4.4 -f points at the repository Dockerfile" -f "$REPO_ROOT/Dockerfile"

  # 4.5: docker missing from PATH
  make_tmp_dir || { fail "4.5 create temp dir"; return; }
  out_file=$TMP_DIR/stdout
  err_file=$TMP_DIR/stderr
  PATH=$TMP_DIR/does-not-exist "$SH" "$BUILD_SCRIPT" >"$out_file" 2>"$err_file"
  assert_ne "4.5 missing docker exits non-zero" 0 $?
  assert_file_contains "4.5 stderr mentions docker" "$err_file" docker
  if [ -s "$out_file" ]; then
    fail "4.5 stdout is empty" "got '$(cat "$out_file")'"
  else
    pass "4.5 stdout is empty"
  fi

  # 4.6: docker build failure is propagated
  : > "$STUB_LOG"
  PATH=$stub_path STUB_EXIT=1 "$BUILD_SCRIPT" >/dev/null 2>&1
  assert_ne "4.6 failing docker build exits non-zero" 0 $?

  # 4.7: --help prints usage to stdout and does not call docker
  : > "$STUB_LOG"
  help_out=$(PATH=$stub_path "$BUILD_SCRIPT" --help 2>/dev/null)
  assert_eq "4.7 --help exits 0" 0 $?
  case $help_out in
    *Usage*) pass "4.7 --help prints Usage to stdout" ;;
    *)       fail "4.7 --help prints Usage to stdout" "got '$help_out'" ;;
  esac
  assert_eq "4.7 --help does not call docker" "" "$(cat "$STUB_LOG")"
  PATH=$stub_path "$BUILD_SCRIPT" -h >/dev/null 2>&1
  assert_eq "4.7 -h exits 0" 0 $?

  # More than one argument
  : > "$STUB_LOG"
  PATH=$stub_path "$BUILD_SCRIPT" 1.0.0 extra >/dev/null 2>&1
  assert_eq "more than one argument exits 2" 2 $?
  assert_eq "more than one argument does not call docker" "" "$(cat "$STUB_LOG")"
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

  # 4.1: build script without arguments
  if "$BUILD_SCRIPT" >/dev/null 2>&1; then
    pass "4.1 scripts/docker-build.sh exits 0"
  else
    fail "4.1 scripts/docker-build.sh exits 0"
  fi
  assert_success "4.1 image $IMAGE exists" docker image inspect "$IMAGE"

  # 4.2: build script with a version-like tag (test-1.0.0, removed on exit)
  tmp_image 1.0.0
  script_tag=${TMP_IMAGE#*:}
  if "$BUILD_SCRIPT" "$script_tag" >/dev/null 2>&1; then
    pass "4.2 scripts/docker-build.sh $script_tag exits 0"
  else
    fail "4.2 scripts/docker-build.sh $script_tag exits 0"
  fi
  assert_success "4.2 image $TMP_IMAGE exists" docker image inspect "$TMP_IMAGE"

  # 4.4: build script called from another directory
  make_tmp_dir || { fail "4.4 create temp dir"; return; }
  tmp_image other-dir
  if (cd "$TMP_DIR" && "$BUILD_SCRIPT" "${TMP_IMAGE#*:}" >/dev/null 2>&1); then
    pass "4.4 scripts/docker-build.sh from another directory exits 0"
  else
    fail "4.4 scripts/docker-build.sh from another directory exits 0"
  fi
  assert_success "4.4 image $TMP_IMAGE exists" docker image inspect "$TMP_IMAGE"

  # 4.3: IMAGE_NAME overrides the image name (removed on exit)
  custom_image=test-workspace-custom:test-image-name
  TMP_IMAGES="$TMP_IMAGES $custom_image"
  if IMAGE_NAME=${custom_image%%:*} "$BUILD_SCRIPT" "${custom_image#*:}" >/dev/null 2>&1; then
    pass "4.3 IMAGE_NAME=${custom_image%%:*} scripts/docker-build.sh exits 0"
  else
    fail "4.3 IMAGE_NAME=${custom_image%%:*} scripts/docker-build.sh exits 0"
  fi
  assert_success "4.3 image $custom_image exists" docker image inspect "$custom_image"

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
