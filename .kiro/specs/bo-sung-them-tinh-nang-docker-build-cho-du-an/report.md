# bổ sung thêm tính năng docker build cho dự án

> bổ sung thêm tính năng docker build cho dự án

## Tóm tắt

- Dự án: test-workspace, branch `feature/FR-20260929-001` → `master`
- Task: 2/2 đã tích hợp
- Agent đã dùng: claude
- Số lần chờ quota: 1
- Review: đạt

## Task

| # | Task | Agent | Lần thử | Trạng thái |
| --- | --- | --- | --- | --- |
| 1 | Tạo Dockerfile, .dockerignore, mục Docker trong README và bộ kiểm thử nền | claude | 1 | đã tích hợp |
| 2 | Viết script build `scripts/docker-build.sh` và kiểm thử cho script | claude | 1 | đã tích hợp |

## Giả định

- Repository hiện chỉ có `README.md`, chưa có mã ứng dụng hay ngôn ngữ/stack cụ thể; vì vậy image dùng một base image nhỏ, phổ biến (ví dụ `alpine` với tag cố định phiên bản) và chỉ sao chép nội dung dự án vào thư mục làm việc `/app`.
- Lệnh mặc định của container (CMD) là một lệnh đơn giản, kết thúc với mã thoát 0 (ví dụ liệt kê/hiển thị nội dung `/app`), cho đến khi dự án có ứng dụng thực sự; khi đó CMD sẽ được cập nhật.
- `Dockerfile` và `.dockerignore` đặt tại thư mục gốc của repository; build context là thư mục gốc.
- Script build đặt tại `scripts/docker-build.sh`, viết bằng POSIX shell, chạy được trên macOS và Linux.
- Tên image mặc định là `test-workspace` và tag mặc định là `latest`.
- Môi trường chạy build/test đã cài Docker Engine (hoặc Docker Desktop) hỗ trợ BuildKit.
- Ngoài phạm vi (out of scope): đẩy image lên registry (`docker push`), build đa kiến trúc (multi-platform/buildx), `docker-compose`, pipeline CI/CD, quét lỗ hổng bảo mật image, và triển khai (deploy).

## Kiểm thử

Bộ kiểm thử:

- `tests/docker-build.test.sh`: bộ kiểm thử POSIX shell chứa các kiểm tra thực tế (tĩnh, stub `docker`, tích hợp Docker thật).
- `tests/docker-build.test.mjs`: điểm vào `node:test` (không cần phụ thuộc ngoài) chạy bộ shell một lần và báo cáo một test cho mỗi tiêu chí (`criterion <id>`); tiêu chí chỉ đạt khi có ít nhất một kiểm tra PASS và không có FAIL/SKIP.

Cách chạy: `npm test` (script `"test"` trong `package.json`), hoặc trực tiếp `sh tests/docker-build.test.sh`. Cần Docker daemon cho nhóm tích hợp.

Kết quả lần chạy ngày 2026-09-29 với Docker daemon thật:

- `npm test`: **22 đạt, 0 lỗi** (1 test mã thoát bộ shell + 21 test theo tiêu chí).
- `sh tests/docker-build.test.sh`: **51 đạt, 0 lỗi, 0 bỏ qua** (mã thoát 0).

| Criterion | Test | Kết quả |
| --- | --- | --- |
| 1.1 | tests/docker-build.test.mjs › criterion 1.1; tests/docker-build.test.sh › 1.1 docker build -t test-workspace:latest . exits 0; 1.1 docker image inspect test-workspace:latest succeeds | đạt |
| 1.2 | tests/docker-build.test.mjs › criterion 1.2; tests/docker-build.test.sh › 1.2 FROM base image has a pinned tag (alpine:3.20) | đạt |
| 1.3 | tests/docker-build.test.mjs › criterion 1.3; tests/docker-build.test.sh › 1.3 Config.WorkingDir is /app | đạt |
| 1.4 | tests/docker-build.test.mjs › criterion 1.4; tests/docker-build.test.sh › 1.4 label org.opencontainers.image.title is test-workspace | đạt |
| 1.5 | tests/docker-build.test.mjs › criterion 1.5; tests/docker-build.test.sh › 1.5 docker build fails on a syntax error (FROMM); 1.5 docker build fails when a step fails (RUN exit 1) | đạt |
| 2.1 | tests/docker-build.test.mjs › criterion 2.1; tests/docker-build.test.sh › 2.1 docker run --rm test-workspace:latest exits 0 | đạt |
| 2.2 | tests/docker-build.test.mjs › criterion 2.2; tests/docker-build.test.sh › 2.2 container runs as non-root (id -u = 100) | đạt |
| 2.3 | tests/docker-build.test.mjs › criterion 2.3; tests/docker-build.test.sh › 2.3 /app/README.md exists | đạt |
| 3.1 | tests/docker-build.test.mjs › criterion 3.1; tests/docker-build.test.sh › 3.1 /app/.git is absent | đạt |
| 3.2 | tests/docker-build.test.mjs › criterion 3.2; tests/docker-build.test.sh › 3.2 /app/.kiro is absent | đạt |
| 3.3 | tests/docker-build.test.mjs › criterion 3.3; tests/docker-build.test.sh › 3.3 /app/.env is absent when the context has .env | đạt |
| 3.4 | tests/docker-build.test.mjs › criterion 3.4; tests/docker-build.test.sh › 3.4 .dockerignore contains '.git' / '.kiro' / '.env' | đạt |
| 4.1 | tests/docker-build.test.mjs › criterion 4.1; tests/docker-build.test.sh › 4.1 no arguments exits 0; 4.1 docker called with '-t test-workspace:latest' (stub); 4.1 scripts/docker-build.sh exits 0; 4.1 image test-workspace:latest exists | đạt |
| 4.2 | tests/docker-build.test.mjs › criterion 4.2; tests/docker-build.test.sh › 4.2 tag 1.0.0 exits 0; 4.2 docker called with '-t test-workspace:1.0.0' (stub); 4.2 scripts/docker-build.sh test-1.0.0 exits 0; 4.2 image test-workspace:test-1.0.0 exists | đạt |
| 4.3 | tests/docker-build.test.mjs › criterion 4.3; tests/docker-build.test.sh › 4.3 docker called with '-t my-image:1.0.0' (stub); 4.3 IMAGE_NAME=test-workspace-custom scripts/docker-build.sh exits 0; 4.3 image test-workspace-custom:test-image-name exists | đạt |
| 4.4 | tests/docker-build.test.mjs › criterion 4.4; tests/docker-build.test.sh › 4.4 build context is the repository root; 4.4 -f points at the repository Dockerfile (stub); 4.4 scripts/docker-build.sh from another directory exits 0; 4.4 image test-workspace:test-other-dir exists | đạt |
| 4.5 | tests/docker-build.test.mjs › criterion 4.5; tests/docker-build.test.sh › 4.5 missing docker exits non-zero; 4.5 stderr mentions docker; 4.5 stdout is empty | đạt |
| 4.6 | tests/docker-build.test.mjs › criterion 4.6; tests/docker-build.test.sh › 4.6 failing docker build exits non-zero | đạt |
| 4.7 | tests/docker-build.test.mjs › criterion 4.7; tests/docker-build.test.sh › 4.7 --help exits 0; 4.7 --help prints Usage to stdout; 4.7 --help does not call docker | đạt |
| 5.1 | tests/docker-build.test.mjs › criterion 5.1; tests/docker-build.test.sh › 5.1 README.md has a heading containing 'Docker' | đạt |
| 5.2 | tests/docker-build.test.mjs › criterion 5.2; tests/docker-build.test.sh › 5.2 README.md contains 'docker build' / 'docker run' / 'scripts/docker-build.sh' | đạt |

Ghi chú:

- Kiểm tra cú pháp (thay cho type checking): `sh -n scripts/docker-build.sh`, `sh -n tests/docker-build.test.sh` và `node --check tests/docker-build.test.mjs` đều đạt.
- Bổ sung `package.json` với script `"test"` để dự án có lệnh kiểm thử chuẩn (`npm test`).
- Bổ sung trong đợt QA: kiểm thử tích hợp với Docker thật cho 4.3 (build với `IMAGE_NAME` tuỳ chỉnh và xác nhận image tồn tại) và kiểm tra image tồn tại sau khi chạy script từ thư mục khác (4.4).
- Không phát hiện lỗi trong mã sản phẩm; không sửa `Dockerfile`, `.dockerignore`, `README.md` hay `scripts/docker-build.sh`.
- Các image tạm (tag `test-*`, `test-workspace-custom:*`) và thư mục tạm được dọn tự động khi bộ kiểm thử kết thúc.

## Review

- **major** `Dockerfile:1`: Base image alpine:3.20 đã hết hạn hỗ trợ (EOL khoảng 2026-04-01), không còn nhận bản vá bảo mật. Nâng lên nhánh Alpine còn được hỗ trợ (ví dụ alpine:3.22+), cân nhắc ghim digest, và cập nhật chuỗi alpine:3.20 trong kiểm thử 1.5 và design.
- **minor** `Dockerfile:9`: COPY --chown=app:app khiến user runtime ghi được vào mã nguồn trong /app (đã kiểm chứng touch /app/README.md thành công). Bỏ --chown để tệp thuộc root, user app vẫn đọc được — tuân theo nguyên tắc quyền tối thiểu.
- **minor** `.dockerignore:4`: Chỉ loại .env ở gốc; .env trong thư mục con vẫn vào image, và tests/, package.json cũng bị sao chép. Bổ sung **/.env, **/.env.*, node_modules và cân nhắc loại tests, package.json (giữ README.md).
- **minor** `scripts/docker-build.sh:49`: Xác định thư mục script bằng ${0%/*} sẽ sai khi gọi qua symlink (build context thành thư mục cha của symlink). Ghi chú giới hạn này hoặc xử lý symlink nếu cần hỗ trợ.
- **minor** `scripts/docker-build.sh:45`: Không kiểm tra IMAGE_NAME; giá trị có sẵn tag (ví dụ foo:bar) tạo tham chiếu foo:bar:latest và docker báo lỗi khó hiểu. Thêm kiểm tra đơn giản và báo lỗi rõ ràng, hoặc ghi rõ trong --help.
- **minor** `tests/docker-build.test.sh:317`: Kiểm thử tích hợp (1.1, 4.1) build lại và ghi đè image test-workspace:latest của người dùng mà không dọn. Chấp nhận được vì AC yêu cầu đúng tên này, nhưng nên ghi chú ở đầu script kiểm thử và test-report.
- **minor** `package.json:6`: package.json và tests/docker-build.test.mjs nằm ngoài design/tasks, thêm phụ thuộc Node chỉ để bọc bộ kiểm thử shell, và package.json bị sao chép vào image. Cập nhật design để phản ánh, hoặc thêm package.json vào .dockerignore.

## Thay đổi

```
.dockerignore                                      |   4 +
 .../design.md                                      | 245 ++++++++++++
 .../requirements.md                                |  73 ++++
 .../review.md                                      |  84 ++++
 .../tasks.md                                       |  31 ++
 .../test-report.md                                 |  45 +++
 Dockerfile                                         |  13 +
 README.md                                          |  23 ++
 package.json                                       |   8 +
 scripts/docker-build.sh                            |  56 +++
 tests/docker-build.test.mjs                        |  38 ++
 tests/docker-build.test.sh                         | 429 +++++++++++++++++++++
 12 files changed, 1049 insertions(+)
```

## Tài liệu

- [Requirements](.kiro/specs/bo-sung-them-tinh-nang-docker-build-cho-du-an/requirements.md)
- [Design](.kiro/specs/bo-sung-them-tinh-nang-docker-build-cho-du-an/design.md)
- [Tasks](.kiro/specs/bo-sung-them-tinh-nang-docker-build-cho-du-an/tasks.md)
- [Test report](.kiro/specs/bo-sung-them-tinh-nang-docker-build-cho-du-an/test-report.md)
- [Review](.kiro/specs/bo-sung-them-tinh-nang-docker-build-cho-du-an/review.md)

---

Tạo bởi AI Orchestrator (FR-20260929-001).
