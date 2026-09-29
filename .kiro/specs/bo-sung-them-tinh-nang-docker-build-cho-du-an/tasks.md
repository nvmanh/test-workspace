# Implementation Plan

- [ ] 1. Tạo Dockerfile, .dockerignore, mục Docker trong README và bộ kiểm thử nền
  - Tạo `Dockerfile` ở gốc repository đúng như design: `FROM alpine:3.20` (tag cố định, không dùng `latest`), `LABEL org.opencontainers.image.title="test-workspace"`, `WORKDIR /app`, tạo system user/group `app` bằng `addgroup -S` / `adduser -S -G app app`, `COPY --chown=app:app . /app`, `USER app`, `CMD ["ls", "-la", "/app"]`.
  - Tạo `.dockerignore` ở gốc repository, mỗi mục một dòng: `.git`, `.kiro`, `.env`, `.env.*`. Không loại `README.md` (cần cho Req 2.3).
  - Giữ nguyên dòng tiêu đề hiện có của `README.md`, thêm mục `## Docker` với ví dụ `docker build -t test-workspace:latest .`, các cách gọi `scripts/docker-build.sh` (không tham số, với tag `1.0.0`, với `IMAGE_NAME=my-image`, với `--help`) và `docker run --rm test-workspace:latest`.
  - Tạo `tests/docker-build.test.sh` (POSIX shell, chạy được từ bất kỳ thư mục nào, tự tính gốc repo từ vị trí script) gồm: các hàm trợ giúp `pass`, `fail`, `assert_*`, bộ đếm lỗi, `trap` dọn image tạm (tag bắt đầu bằng `test-`) và thư mục tạm; kết thúc mã khác 0 nếu có ca thất bại. Cấu trúc theo ba nhóm (tĩnh / stub docker / tích hợp Docker thật) để task 2 bổ sung ca kiểm thử cho script build.
  - Nhóm tĩnh: dòng `FROM` có tag và không kết thúc bằng `:latest` (1.2); `.dockerignore` chứa đủ dòng `.git`, `.kiro`, `.env` (3.4); `README.md` có tiêu đề Markdown chứa chữ `Docker` (5.1) và chứa `docker build`, `docker run`, `scripts/docker-build.sh` (5.2).
  - Nhóm tích hợp (cần Docker daemon; nếu không có daemon thì FAIL, trừ khi `ALLOW_SKIP_DOCKER=1` thì báo SKIP): `docker build -t test-workspace:latest .` thoát 0 và `docker image inspect` thành công (1.1); `Config.WorkingDir` bằng `/app` (1.3); label `org.opencontainers.image.title` bằng `test-workspace` (1.4); Dockerfile lỗi cú pháp (`FROMM`) và Dockerfile có `RUN exit 1` trong thư mục tạm đều build với mã khác 0 (1.5); `docker run --rm test-workspace:latest` thoát 0 (2.1); `id -u` khác `0` (2.2); `test -f /app/README.md` thoát 0 (2.3); `test ! -e /app/.git` và `test ! -e /app/.kiro` thoát 0 (3.1, 3.2); sao chép build context vào thư mục tạm, tạo `.env` giả, build tag `test-env` và kiểm tra `test ! -e /app/.env` thoát 0 — không tạo `.env` trong workspace thật (3.3).
  - Kiểm tra cú pháp bằng `sh -n tests/docker-build.test.sh`, chạy bộ kiểm thử và xác nhận tất cả ca PASS.
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 3.4, 5.1, 5.2_
  - _Files: Dockerfile (new), .dockerignore (new), README.md, tests/docker-build.test.sh (new)_
  - _Agent: claude_

- [ ] 2. Viết script build `scripts/docker-build.sh` và kiểm thử cho script
  - Tạo `scripts/docker-build.sh` (shebang `#!/bin/sh`, `set -eu`, chỉ dùng cú pháp POSIX, `chmod +x`) theo đúng thứ tự hành vi trong design:
    1. Tham số thứ nhất là `-h` hoặc `--help` → in usage (chứa `Usage`) ra stdout, không gọi docker, thoát 0.
    2. Nhiều hơn 1 tham số → in lỗi và usage ra stderr, thoát 2.
    3. `command -v docker` thất bại → in `Error: 'docker' command not found in PATH` ra stderr, thoát 127.
    4. `IMAGE_NAME` mặc định `test-workspace`, `TAG` mặc định `latest` (lấy từ tham số thứ nhất nếu có).
    5. Xác định thư mục script bằng parameter expansion của `$0` (không dùng `dirname`), `REPO_ROOT=$(cd "$script_dir/.." && pwd -P)`.
    6. `exec docker build -t "$IMAGE_NAME:$TAG" -f "$REPO_ROOT/Dockerfile" "$REPO_ROOT"` để mã thoát của script là mã thoát của `docker build`.
  - Bổ sung vào `tests/docker-build.test.sh`:
    - Nhóm stub (tạo tệp thực thi `docker` giả trong thư mục tạm, ghi tham số vào log, mã thoát tuỳ cấu hình, đặt làm `PATH`): không tham số → log chứa `-t test-workspace:latest`, thoát 0 (4.1); tag `1.0.0` → log chứa `test-workspace:1.0.0` (4.2); `IMAGE_NAME=my-image` với tag `1.0.0` → log chứa `my-image:1.0.0` (4.3); `cd` vào thư mục tạm rồi gọi script bằng đường dẫn tuyệt đối → tham số context bằng gốc repo (`pwd -P`) và `-f` trỏ tới `Dockerfile` ở gốc repo (4.4); `PATH` trỏ tới thư mục không tồn tại → mã khác 0, stderr chứa `docker`, stdout rỗng (4.5); stub trả mã 1 → script trả mã khác 0 (4.6); `--help` → thoát 0, stdout chứa `Usage`, log stub rỗng (4.7); nhiều hơn một tham số → thoát 2.
    - Nhóm tích hợp: chạy script thật không tham số → thoát 0 và image `test-workspace:latest` tồn tại (4.1); build với tag tạm dạng phiên bản (tên bắt đầu bằng `test-` hoặc được dọn bởi `trap`) → thoát 0 và image tồn tại (4.2); gọi script từ thư mục khác gốc repo → build thoát 0 (4.4).
    - Thêm `sh -n scripts/docker-build.sh` vào bước kiểm tra cú pháp.
  - Chạy `sh -n` cho cả hai script và chạy toàn bộ bộ kiểm thử, xác nhận tất cả ca PASS.
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7_
  - _Files: scripts/docker-build.sh (new), tests/docker-build.test.sh_
  - _Depends: 1_
  - _Agent: claude_
