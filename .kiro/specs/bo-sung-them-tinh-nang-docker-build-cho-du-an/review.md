# Code Review: bổ sung thêm tính năng docker build cho dự án

Phạm vi: toàn bộ thay đổi trên nhánh `feature/FR-20260929-001` so với `master` (`Dockerfile`, `.dockerignore`, `README.md`, `package.json`, `scripts/docker-build.sh`, `tests/docker-build.test.sh`, `tests/docker-build.test.mjs` và tài liệu spec trong `.kiro/`).

## Kiểm chứng đã thực hiện

Chạy trên macOS với Docker daemon thật (ngày 2026-09-29):

- `sh tests/docker-build.test.sh` → **51 passed, 0 failed, 0 skipped**.
- `npm test` → **22 pass, 0 fail**.
- `node --check tests/docker-build.test.mjs`, `sh -n` cho hai script shell → đạt.
- Kiểm tra thủ công image `test-workspace:latest`: `Config.User = app`, `Config.Cmd = ["ls","-la","/app"]`, `docker run --rm test-workspace:latest` liệt kê `/app` gồm `.dockerignore`, `Dockerfile`, `README.md`, `package.json`, `scripts/`, `tests/` (không có `.git`, `.kiro`, `.env`).

## Đối chiếu acceptance criteria

| AC | Kết quả | Ghi chú |
|----|---------|---------|
| 1.1 | Đạt | `docker build -t test-workspace:latest .` thoát 0, `docker image inspect` thành công |
| 1.2 | Đạt | `FROM alpine:3.20` — có tag, không phải `latest` (xem vấn đề về EOL bên dưới) |
| 1.3 | Đạt | `Config.WorkingDir` = `/app` |
| 1.4 | Đạt | Label `org.opencontainers.image.title` = `test-workspace` |
| 1.5 | Đạt | `FROMM` và `RUN exit 1` đều làm build thất bại |
| 2.1 | Đạt | CMD `ls -la /app` thoát 0 |
| 2.2 | Đạt | `id -u` = 100 |
| 2.3 | Đạt | `/app/README.md` tồn tại |
| 3.1 | Đạt | `.git` (kể cả dạng tệp của git worktree) bị loại |
| 3.2 | Đạt | `.kiro` bị loại |
| 3.3 | Đạt | Kiểm thử bằng bản sao context có `.env` giả, không đụng workspace thật |
| 3.4 | Đạt | `.dockerignore` có đủ dòng `.git`, `.kiro`, `.env` |
| 4.1 | Đạt | Stub + tích hợp |
| 4.2 | Đạt | Stub (`1.0.0`) + tích hợp (`test-1.0.0`) |
| 4.3 | Đạt | Stub (`my-image`) + tích hợp (`test-workspace-custom`) |
| 4.4 | Đạt | Context và `-f` trỏ về gốc repo khi chạy từ thư mục khác |
| 4.5 | Đạt | Thông báo lỗi ra stderr, mã 127, stdout rỗng |
| 4.6 | Đạt | `exec docker build` truyền nguyên mã thoát |
| 4.7 | Đạt | `--help`/`-h` in usage ra stdout, thoát 0, không gọi docker |
| 5.1 | Đạt | Có mục `## Docker` |
| 5.2 | Đạt | Có `docker build`, `docker run`, `scripts/docker-build.sh` |

Tất cả acceptance criteria đều được đáp ứng và có kiểm thử tự động tương ứng. Không phát hiện hành vi sai hay lỗ hổng bảo mật ở mức phải chặn merge.

## Nhận xét chi tiết

### Điểm tốt

- Script build ngắn gọn, đúng POSIX, `set -eu`, thứ tự xử lý tham số đúng design; dùng `exec` để giữ mã thoát của `docker build`.
- Xác định `REPO_ROOT` không cần lệnh ngoài, nên kiểm thử 4.5 với `PATH` rỗng vẫn chạy đúng tới bước kiểm tra docker.
- Bộ kiểm thử có 3 nhóm rõ ràng, stub docker ghi từng tham số nên kiểm tra được cặp `-t`/`-f` và context chính xác; có `trap` dọn image/thư mục tạm; không có daemon thì FAIL thay vì im lặng bỏ qua (trừ khi đặt `ALLOW_SKIP_DOCKER=1`).
- Chạy container bằng user không phải root, base image có tag cố định.

### Vấn đề (không phải blocker)

1. **[major] `Dockerfile:1` — `alpine:3.20` đã hết hạn hỗ trợ.** Alpine 3.20 hết hạn hỗ trợ (EOL) khoảng 2026-04-01, nên tại thời điểm review (2026-09-29) nhánh này không còn nhận bản vá bảo mật. Yêu cầu 1.2 chỉ bắt buộc có tag cố định nên AC vẫn đạt, nhưng mục tiêu "an toàn" trong requirements bị ảnh hưởng. Đề xuất: nâng lên nhánh Alpine còn được hỗ trợ (ví dụ `alpine:3.22` hoặc mới hơn), cân nhắc ghim thêm digest (`alpine:3.x@sha256:...`) để build tái lập được; cập nhật các chuỗi `alpine:3.20` trong kiểm thử 1.5 và trong design cho khớp.

2. **[minor] `Dockerfile:9` — tệp trong `/app` thuộc sở hữu của user runtime.** `COPY --chown=app:app` làm tiến trình chạy trong container sửa được mã nguồn/cấu hình của chính nó (đã kiểm chứng: `touch /app/README.md` thành công khi chạy bằng user `app`). Với image chỉ cần đọc, nên để tệp thuộc root (bỏ `--chown`, quyền mặc định 644/755 vẫn cho user `app` đọc được) để tuân theo nguyên tắc quyền tối thiểu.

3. **[minor] `.dockerignore:4` — chưa loại các tệp không cần thiết/nhạy cảm khác.** Chỉ loại `.env` ở gốc; `.env` trong thư mục con (ví dụ `scripts/.env`) vẫn vào image. Các tệp phục vụ phát triển (`tests/`, `package.json`, `node_modules` nếu có sau này) cũng bị sao chép vào image. Đề xuất bổ sung `**/.env`, `**/.env.*`, `node_modules` và cân nhắc loại `tests`/`package.json` (vẫn giữ `README.md` cho Req 2.3). Lưu ý kiểm thử 3.3 hiện đang sao chép cả `tests` vào context tạm.

4. **[minor] `scripts/docker-build.sh:49` — xác định thư mục gốc sai khi gọi qua symlink.** `${0%/*}` lấy thư mục chứa symlink chứ không phải thư mục chứa script thật; nếu người dùng tạo symlink (ví dụ `~/bin/docker-build -> .../scripts/docker-build.sh`) thì build context bị tính sai. Đây là giới hạn chấp nhận được theo design; nên ghi chú trong usage/README hoặc xử lý symlink nếu cần.

5. **[minor] `scripts/docker-build.sh:45` — không kiểm tra đầu vào `IMAGE_NAME`.** Nếu người dùng đặt `IMAGE_NAME=foo:bar`, tham chiếu thành `foo:bar:latest` và docker báo lỗi khó hiểu. Hành vi vẫn đúng Req 4.6 (thoát khác 0); có thể thêm kiểm tra đơn giản `case $IMAGE_NAME in *:*) ...` để báo lỗi rõ ràng hơn, hoặc ghi rõ trong `--help`.

6. **[minor] `tests/docker-build.test.sh:317` — kiểm thử tích hợp ghi đè image `test-workspace:latest` thật của người dùng.** Các bước 1.1 và 4.1 build lại và không dọn `test-workspace:latest`. Đây là do AC yêu cầu đúng tên image này nên chấp nhận được, nhưng nên ghi chú trong phần đầu script kiểm thử/test-report để người chạy biết.

7. **[minor] `package.json:6` — thay đổi ngoài design.** `package.json` và `tests/docker-build.test.mjs` không có trong design/tasks (được thêm ở bước QA để có `npm test`). Không gây hại và đã chạy đạt, nhưng tạo phụ thuộc vào Node chỉ để bọc một bộ kiểm thử shell, và `package.json` bị sao chép vào image. Nên cập nhật design (mục Testing Strategy) để phản ánh điều này, hoặc thêm `package.json` vào `.dockerignore`.

## Kết luận

Triển khai đúng design và đạt đủ 21 acceptance criteria, đã kiểm chứng lại bằng Docker thật. Không có blocker. Nên xử lý vấn đề major về base image đã EOL trong lần cập nhật gần nhất; các vấn đề minor có thể làm sau.

```json
{
  "verdict": "approve",
  "issues": [
    { "severity": "major", "file": "Dockerfile", "line": 1, "message": "Base image alpine:3.20 đã hết hạn hỗ trợ (EOL khoảng 2026-04-01), không còn nhận bản vá bảo mật. Nâng lên nhánh Alpine còn được hỗ trợ (ví dụ alpine:3.22+), cân nhắc ghim digest, và cập nhật chuỗi alpine:3.20 trong kiểm thử 1.5 và design." },
    { "severity": "minor", "file": "Dockerfile", "line": 9, "message": "COPY --chown=app:app khiến user runtime ghi được vào mã nguồn trong /app (đã kiểm chứng touch /app/README.md thành công). Bỏ --chown để tệp thuộc root, user app vẫn đọc được — tuân theo nguyên tắc quyền tối thiểu." },
    { "severity": "minor", "file": ".dockerignore", "line": 4, "message": "Chỉ loại .env ở gốc; .env trong thư mục con vẫn vào image, và tests/, package.json cũng bị sao chép. Bổ sung **/.env, **/.env.*, node_modules và cân nhắc loại tests, package.json (giữ README.md)." },
    { "severity": "minor", "file": "scripts/docker-build.sh", "line": 49, "message": "Xác định thư mục script bằng ${0%/*} sẽ sai khi gọi qua symlink (build context thành thư mục cha của symlink). Ghi chú giới hạn này hoặc xử lý symlink nếu cần hỗ trợ." },
    { "severity": "minor", "file": "scripts/docker-build.sh", "line": 45, "message": "Không kiểm tra IMAGE_NAME; giá trị có sẵn tag (ví dụ foo:bar) tạo tham chiếu foo:bar:latest và docker báo lỗi khó hiểu. Thêm kiểm tra đơn giản và báo lỗi rõ ràng, hoặc ghi rõ trong --help." },
    { "severity": "minor", "file": "tests/docker-build.test.sh", "line": 317, "message": "Kiểm thử tích hợp (1.1, 4.1) build lại và ghi đè image test-workspace:latest của người dùng mà không dọn. Chấp nhận được vì AC yêu cầu đúng tên này, nhưng nên ghi chú ở đầu script kiểm thử và test-report." },
    { "severity": "minor", "file": "package.json", "line": 6, "message": "package.json và tests/docker-build.test.mjs nằm ngoài design/tasks, thêm phụ thuộc Node chỉ để bọc bộ kiểm thử shell, và package.json bị sao chép vào image. Cập nhật design để phản ánh, hoặc thêm package.json vào .dockerignore." }
  ]
}
```
