# Design Document

## Overview

Tính năng bổ sung khả năng đóng gói repository "test-workspace" thành Docker image. Hiện trạng repository (kiểm tra bằng git ls-files) chỉ gồm:

- `README.md` — chỉ có một dòng tiêu đề "# Agent Test".
- `.kiro/specs/bo-sung-them-tinh-nang-docker-build-cho-du-an/requirements.md` — tài liệu yêu cầu.

Không có mã ứng dụng, không có manifest của ngôn ngữ nào, không có test framework và không có build tool. Vì vậy thiết kế chọn thay đổi nhỏ nhất thỏa mãn toàn bộ acceptance criteria:

1. `Dockerfile` (new) — một stage duy nhất trên base image Alpine với tag phiên bản cố định (3.20), sao chép dự án vào thư mục /app, chạy bằng user không phải root, CMD liệt kê nội dung /app.
2. `.dockerignore` (new) — loại .git, .kiro, .env (và biến thể .env.*) khỏi build context.
3. `scripts/docker-build.sh` (new) — script POSIX shell bọc lệnh docker build, hỗ trợ tag tuỳ chọn, biến môi trường `IMAGE_NAME`, cờ `--help`, luôn dùng thư mục gốc repository làm build context.
4. `README.md` — bổ sung mục "## Docker" với ví dụ docker build, docker run và cách gọi script build.
5. `tests/docker-build.test.sh` (new) — bộ kiểm thử bằng POSIX shell để kiểm chứng từng acceptance criterion.

Ngoài phạm vi (theo requirements): docker push, multi-platform/buildx, docker-compose, CI/CD, quét lỗ hổng, deploy.

## Architecture

Luồng build và chạy:

    Lập trình viên / CI
       |
       |-- docker build -t test-workspace:latest .      (gọi trực tiếp, Req 1)
       |
       '-- scripts/docker-build.sh [tag | --help]        (Req 4)
             1. Phân tích tham số (--help / tag / quá nhiều tham số)
             2. Kiểm tra docker có trong PATH (command -v)
             3. Xác định REPO_ROOT = thư mục cha của thư mục chứa script
             4. docker build -t "$IMAGE_NAME:$TAG" -f "$REPO_ROOT/Dockerfile" "$REPO_ROOT"
       v
    Docker Engine (BuildKit)
       đọc .dockerignore -> loại .git, .kiro, .env, .env.*
       đọc Dockerfile
       v
    Image test-workspace:<tag>
       FROM alpine:3.20
       LABEL org.opencontainers.image.title="test-workspace"
       WORKDIR /app
       user/group app (system, UID khác 0)
       COPY --chown=app:app . /app
       USER app
       CMD ["ls", "-la", "/app"]   -> thoát với mã 0

Quyết định thiết kế:

- **Base image Alpine 3.20** (tag cố định, không dùng latest — Req 1.2): nhỏ (~7 MB), phổ biến, có sẵn ls, id, test, adduser, addgroup (BusyBox) — đủ cho mọi lệnh kiểm chứng trong requirements (id -u, test -f, test ! -e).
- **Single-stage**: dự án không có bước biên dịch nên multi-stage là thừa.
- **User không phải root**: tạo system user app bằng addgroup -S / adduser -S (UID do Alpine cấp, luôn khác 0) rồi chỉ thị USER app (Req 2.2). COPY dùng --chown=app:app để user app đọc được tệp.
- **Build context là thư mục gốc**: `Dockerfile` (new) và `.dockerignore` (new) đặt ở gốc repository (theo Assumptions). Script tự tính đường dẫn gốc từ vị trí của chính nó nên chạy được từ bất kỳ thư mục nào (Req 4.4).
- **Script chỉ dùng shell builtin và docker**: thư mục chứa script được xác định bằng parameter expansion của biến $0 thay vì lệnh dirname, để khi kiểm thử Req 4.5 với PATH không chứa docker, script vẫn chạy tới bước kiểm tra docker và in lỗi đúng.

## Components and Interfaces

### 1. `Dockerfile` (new)

Nội dung dự kiến:

    FROM alpine:3.20

    LABEL org.opencontainers.image.title="test-workspace"

    WORKDIR /app

    RUN addgroup -S app && adduser -S -G app app

    COPY --chown=app:app . /app

    USER app

    CMD ["ls", "-la", "/app"]

- Dòng FROM có tag phiên bản 3.20, không kết thúc bằng :latest (Req 1.2).
- WORKDIR /app → trường Config.WorkingDir của image bằng /app (Req 1.3).
- LABEL → nhãn org.opencontainers.image.title có giá trị test-workspace (Req 1.4).
- CMD dạng exec, lệnh ls luôn có trong Alpine → thoát 0 (Req 2.1). Khi dự án có ứng dụng thực sự, chỉ cần thay CMD.
- Lỗi cú pháp hoặc bước RUN thất bại → docker build tự trả mã khác 0 (Req 1.5), không cần xử lý thêm.

### 2. `.dockerignore` (new)

Nội dung dự kiến (mỗi mục một dòng):

    .git
    .kiro
    .env
    .env.*

- Mục .git khớp cả thư mục .git (repo thường) lẫn tệp .git (git worktree — trường hợp của workspace hiện tại) (Req 3.1).
- Mục .kiro loại toàn bộ tài liệu spec (Req 3.2).
- Mục .env và .env.* loại tệp biến môi trường/bí mật (Req 3.3).
- Chứa đủ ba mục .git, .kiro, .env (Req 3.4).
- `README.md` **không** bị loại vì Req 2.3 yêu cầu tệp README.md tồn tại trong thư mục /app của image.

### 3. `scripts/docker-build.sh` (new)

Tệp có quyền thực thi (chmod +x). Giao diện dòng lệnh:

    Usage: scripts/docker-build.sh [TAG]
           scripts/docker-build.sh -h | --help

    Build Docker image <IMAGE_NAME>:<TAG> from the repository root.

    Arguments:
      TAG           Image tag (default: latest)

    Environment:
      IMAGE_NAME    Image name (default: test-workspace)

Hành vi (theo thứ tự):

| Bước | Điều kiện | Hành động | Mã thoát |
|------|-----------|-----------|----------|
| 1 | Tham số thứ nhất là -h hoặc --help | In usage ra **stdout**, không build | 0 (Req 4.7) |
| 2 | Nhiều hơn 1 tham số | In lỗi + usage ra **stderr** | 2 |
| 3 | command -v docker thất bại | In "Error: 'docker' command not found in PATH" ra **stderr** | 127 (Req 4.5) |
| 4 | — | IMAGE_NAME mặc định là test-workspace, TAG mặc định là latest (lấy từ tham số thứ nhất nếu có) | — (Req 4.1–4.3) |
| 5 | — | REPO_ROOT = thư mục cha của thư mục chứa script, chuẩn hoá bằng cd rồi pwd -P | — (Req 4.4) |
| 6 | — | exec docker build với -t "$IMAGE_NAME:$TAG", -f trỏ tới Dockerfile trong REPO_ROOT, context là REPO_ROOT | mã thoát của docker build (Req 4.6) |

Chi tiết cài đặt:

- Shebang #!/bin/sh, bật set -eu; chỉ dùng cú pháp POSIX (không dùng [[ ]], mảng, local) để chạy trên macOS và Linux.
- Xác định thư mục script mà không cần lệnh ngoài:

      case $0 in
        */*) script_dir=${0%/*} ;;
        *)   script_dir=. ;;
      esac
      REPO_ROOT=$(cd "$script_dir/.." && pwd -P)

- Dùng exec cho docker build để mã thoát của script chính là mã thoát của docker build (khác 0 khi build lỗi — Req 4.6).
- Không tự kiểm tra định dạng tag: tag không hợp lệ sẽ bị docker build từ chối với mã khác 0, đủ đáp ứng Req 4.6 mà không thêm logic.

### 4. `README.md` (sửa)

Giữ nguyên dòng tiêu đề hiện có, thêm mục sau:

    ## Docker

    Build image trực tiếp:

        docker build -t test-workspace:latest .

    Hoặc dùng script (tag mặc định latest, tên image đổi được qua IMAGE_NAME):

        scripts/docker-build.sh
        scripts/docker-build.sh 1.0.0
        IMAGE_NAME=my-image scripts/docker-build.sh 1.0.0
        scripts/docker-build.sh --help

    Chạy container:

        docker run --rm test-workspace:latest

Đáp ứng Req 5.1 (tiêu đề chứa chữ Docker) và Req 5.2 (có docker build, docker run và lệnh gọi script build).

### 5. `tests/docker-build.test.sh` (new)

Bộ kiểm thử POSIX shell, chạy được từ bất kỳ thư mục nào. Mô tả chi tiết ở mục Testing Strategy.

## Data Models

Tính năng không có dữ liệu lưu trữ hay schema. Các "mô hình dữ liệu" là cấu hình và giao diện:

**Tham chiếu image**

| Trường | Nguồn | Mặc định | Ví dụ |
|--------|-------|----------|-------|
| Tên image | biến môi trường IMAGE_NAME | test-workspace | my-image |
| Tag | tham số vị trí thứ nhất của script | latest | 1.0.0 |
| Tham chiếu đầy đủ | IMAGE_NAME:TAG | test-workspace:latest | my-image:1.0.0 |

**Metadata của image (kiểm tra bằng docker image inspect)**

| Trường | Giá trị |
|--------|---------|
| Config.WorkingDir | /app |
| Config.User | app |
| Config.Labels, khoá org.opencontainers.image.title | test-workspace |
| Config.Cmd | ["ls", "-la", "/app"] |

**Nội dung thư mục /app trong image**: mọi tệp của build context trừ các mục trong .dockerignore; với repository sau khi triển khai gồm README.md, Dockerfile, .dockerignore, thư mục scripts và thư mục tests.

**Mã thoát của script build**

| Mã | Ý nghĩa |
|----|---------|
| 0 | Build thành công hoặc --help |
| 2 | Sai cách dùng (quá nhiều tham số) |
| 127 | Không tìm thấy docker trong PATH |
| khác 0 (từ docker) | docker build thất bại |

## Error Handling

| Tình huống | Xử lý | Requirement |
|------------|-------|-------------|
| Dockerfile sai cú pháp hoặc một bước RUN lỗi | docker build tự dừng và trả mã khác 0; không cần xử lý bổ sung | 1.5 |
| docker không có trong PATH | Script in "Error: 'docker' command not found in PATH" ra stderr, thoát 127, không build | 4.5 |
| docker build thất bại (daemon không chạy, tag không hợp lệ, lỗi build...) | exec chuyển nguyên mã thoát khác 0 của docker build ra ngoài; thông báo lỗi của docker giữ nguyên trên stderr | 4.6 |
| Truyền nhiều hơn một tham số | In lỗi và usage ra stderr, thoát 2 | 4 (bảo vệ giao diện) |
| Biến chưa khai báo / lệnh lỗi giữa chừng trong script | set -eu dừng script với mã khác 0 | 4.6 |
| Chạy script từ thư mục khác gốc repository | Không phải lỗi: REPO_ROOT tính từ vị trí script nên build context luôn đúng | 4.4 |
| Có tệp .env, .git hoặc thư mục .kiro trong thư mục làm việc | Bị .dockerignore loại khỏi context, không vào image | 3.1–3.3 |

## Testing Strategy

**Test framework**: dự án hiện chưa có test framework nào (không có manifest ngôn ngữ, không có thư mục test, không có bats). Vì các thành phần đều là Dockerfile, cấu hình và shell script, thiết kế chọn **một script kiểm thử POSIX shell thuần** `tests/docker-build.test.sh` (new) thay vì thêm framework/phụ thuộc mới (như bats-core). Script có các hàm trợ giúp nhỏ pass, fail, assert_*, đếm số ca lỗi và kết thúc với mã khác 0 nếu có ca thất bại.

Cách chạy: gọi sh với đường dẫn tới `tests/docker-build.test.sh` (new) từ bất kỳ thư mục nào.

Script chia làm ba nhóm:

1. **Kiểm tra tĩnh** — chỉ đọc tệp, luôn chạy.
2. **Kiểm tra script với docker giả (stub)** — tạo thư mục tạm chứa tệp thực thi tên docker giả, ghi lại tham số vào một log và trả mã thoát tuỳ cấu hình; đặt thư mục này làm PATH. Không cần Docker daemon, chạy nhanh.
3. **Kiểm tra tích hợp với Docker thật** — cần Docker daemon (docker info thành công). Nếu không có daemon, script báo FAIL cho nhóm này, trừ khi đặt ALLOW_SKIP_DOCKER=1 thì báo SKIP rõ ràng. Các image tạm (tag bắt đầu bằng test-) và thư mục tạm được dọn bằng trap khi kết thúc.

Ngoài ra kiểm tra cú pháp shell bằng sh -n cho `scripts/docker-build.sh` (new) và `tests/docker-build.test.sh` (new) (thay cho type checking, vì dự án không có ngôn ngữ có kiểu). Không có bước build ứng dụng; "build check" chính là docker build.

**Ánh xạ acceptance criteria → ca kiểm thử**

| AC | Nhóm | Cách kiểm thử |
|----|------|---------------|
| 1.1 | Tích hợp | Chạy docker build -t test-workspace:latest tại gốc repo, assert mã thoát 0; assert docker image inspect test-workspace:latest thoát 0 |
| 1.2 | Tĩnh | Lấy dòng FROM trong Dockerfile bằng grep; assert có dấu hai chấm chỉ định tag và không kết thúc bằng :latest |
| 1.3 | Tích hợp | docker image inspect với format lấy Config.WorkingDir, assert bằng /app |
| 1.4 | Tích hợp | docker image inspect với format lấy nhãn org.opencontainers.image.title trong Config.Labels, assert bằng test-workspace |
| 1.5 | Tích hợp | Trong thư mục tạm, tạo Dockerfile lỗi cú pháp (chỉ thị FROMM) và Dockerfile có bước lỗi (RUN exit 1); assert docker build với mỗi tệp trả mã khác 0 |
| 2.1 | Tích hợp | docker run --rm test-workspace:latest thoát 0 |
| 2.2 | Tích hợp | Output của docker run --rm test-workspace:latest id -u khác 0 |
| 2.3 | Tích hợp | docker run --rm test-workspace:latest test -f với tệp README.md trong /app, assert thoát 0 |
| 3.1 | Tích hợp | docker run --rm test-workspace:latest test ! -e với .git trong /app, assert thoát 0 |
| 3.2 | Tích hợp | docker run --rm test-workspace:latest test ! -e với .kiro trong /app, assert thoát 0 |
| 3.3 | Tích hợp | Sao chép build context (Dockerfile, .dockerignore, README.md, thư mục scripts) vào thư mục tạm, tạo tệp .env giả trong đó, build tag test-env; assert test ! -e với .env trong /app của image đó thoát 0. Không tạo .env trong workspace thật |
| 3.4 | Tĩnh | grep -qx từng dòng .git, .kiro, .env trong .dockerignore |
| 4.1 | Stub + Tích hợp | Stub: chạy script không tham số, assert log stub chứa -t test-workspace:latest và thoát 0. Tích hợp: chạy script thật, assert thoát 0 và image test-workspace:latest tồn tại |
| 4.2 | Stub + Tích hợp | Stub: chạy script với tag 1.0.0 → log chứa tham chiếu test-workspace kèm tag 1.0.0. Tích hợp: build với một tag tạm dạng phiên bản, assert thoát 0 và image với tag đó tồn tại |
| 4.3 | Stub | Đặt IMAGE_NAME=my-image rồi chạy script với tag 1.0.0 → log chứa tham chiếu my-image kèm tag 1.0.0 |
| 4.4 | Stub + Tích hợp | cd vào thư mục tạm rồi gọi script bằng đường dẫn tuyệt đối; stub: assert tham số cuối (context) bằng đường dẫn gốc repo (pwd -P) và -f trỏ tới Dockerfile ở gốc repo; tích hợp: assert build thoát 0 |
| 4.5 | Stub | Chạy script bằng sh với PATH trỏ tới thư mục không tồn tại; assert mã thoát khác 0, stderr chứa chuỗi docker, stdout rỗng |
| 4.6 | Stub | Stub docker trả mã 1; assert script trả mã khác 0 |
| 4.7 | Stub | Chạy script với --help và stub; assert thoát 0, stdout chứa Usage, log stub rỗng (không gọi docker build) |
| 5.1 | Tĩnh | grep -Eq tìm dòng tiêu đề Markdown chứa chữ Docker trong `README.md` |
| 5.2 | Tĩnh | grep -q lần lượt docker build, docker run và lệnh gọi script build trong `README.md` |
