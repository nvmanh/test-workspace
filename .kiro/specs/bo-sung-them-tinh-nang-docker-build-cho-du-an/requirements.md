# Requirements Document

## Introduction

Tính năng này bổ sung khả năng đóng gói dự án "test-workspace" thành Docker image bằng lệnh `docker build`. Mục tiêu là giúp lập trình viên và hệ thống CI tạo ra image nhất quán, tái lập được, gọn nhẹ và an toàn từ mã nguồn trong repository, thông qua một `Dockerfile`, một tệp `.dockerignore` và một script build tiện dụng.

## Assumptions

- Repository hiện chỉ có `README.md`, chưa có mã ứng dụng hay ngôn ngữ/stack cụ thể; vì vậy image dùng một base image nhỏ, phổ biến (ví dụ `alpine` với tag cố định phiên bản) và chỉ sao chép nội dung dự án vào thư mục làm việc `/app`.
- Lệnh mặc định của container (CMD) là một lệnh đơn giản, kết thúc với mã thoát 0 (ví dụ liệt kê/hiển thị nội dung `/app`), cho đến khi dự án có ứng dụng thực sự; khi đó CMD sẽ được cập nhật.
- `Dockerfile` và `.dockerignore` đặt tại thư mục gốc của repository; build context là thư mục gốc.
- Script build đặt tại `scripts/docker-build.sh`, viết bằng POSIX shell, chạy được trên macOS và Linux.
- Tên image mặc định là `test-workspace` và tag mặc định là `latest`.
- Môi trường chạy build/test đã cài Docker Engine (hoặc Docker Desktop) hỗ trợ BuildKit.
- Ngoài phạm vi (out of scope): đẩy image lên registry (`docker push`), build đa kiến trúc (multi-platform/buildx), `docker-compose`, pipeline CI/CD, quét lỗ hổng bảo mật image, và triển khai (deploy).

## Requirements

### Requirement 1: Dockerfile build được image

**User Story:** Là lập trình viên, tôi muốn có một `Dockerfile` ở thư mục gốc dự án, để có thể build Docker image của dự án chỉ bằng một lệnh.

#### Acceptance Criteria

1. WHEN người dùng chạy `docker build -t test-workspace:latest .` tại thư mục gốc repository THEN THE SYSTEM SHALL hoàn tất build với mã thoát 0 và image `test-workspace:latest` xuất hiện trong kết quả `docker image inspect test-workspace:latest`.
2. WHEN image được build THEN THE SYSTEM SHALL dùng base image có tag phiên bản cụ thể (không dùng tag `latest`), kiểm chứng được bằng việc dòng `FROM` trong `Dockerfile` không kết thúc bằng `:latest` và có chỉ định tag.
3. WHEN image được build THEN THE SYSTEM SHALL đặt `WORKDIR` là `/app`, kiểm chứng được qua trường `Config.WorkingDir` bằng `/app` trong `docker image inspect`.
4. WHEN image được build THEN THE SYSTEM SHALL gắn label OCI `org.opencontainers.image.title` với giá trị `test-workspace`, kiểm chứng được qua `docker image inspect`.
5. IF `Dockerfile` chứa lỗi cú pháp hoặc một bước build thất bại THEN THE SYSTEM SHALL kết thúc lệnh `docker build` với mã thoát khác 0.

### Requirement 2: Container chạy được và an toàn

**User Story:** Là lập trình viên, tôi muốn container tạo ra từ image chạy được với cấu hình an toàn mặc định, để yên tâm sử dụng image trong các môi trường khác nhau.

#### Acceptance Criteria

1. WHEN người dùng chạy `docker run --rm test-workspace:latest` THEN THE SYSTEM SHALL thực thi lệnh mặc định và kết thúc với mã thoát 0.
2. WHEN container chạy THEN THE SYSTEM SHALL chạy tiến trình bằng người dùng không phải root, kiểm chứng được bằng `docker run --rm test-workspace:latest id -u` trả về giá trị khác `0`.
3. WHEN container chạy THEN THE SYSTEM SHALL chứa tệp `/app/README.md`, kiểm chứng được bằng `docker run --rm test-workspace:latest test -f /app/README.md` trả về mã thoát 0.

### Requirement 3: Loại trừ tệp không cần thiết khỏi build context

**User Story:** Là lập trình viên, tôi muốn có tệp `.dockerignore`, để build context nhỏ gọn và image không chứa tệp nhạy cảm hoặc không liên quan.

#### Acceptance Criteria

1. WHEN image được build THEN THE SYSTEM SHALL không chứa thư mục `.git` trong image, kiểm chứng được bằng `docker run --rm test-workspace:latest test ! -e /app/.git` trả về mã thoát 0.
2. WHEN image được build THEN THE SYSTEM SHALL không chứa thư mục `.kiro` trong image, kiểm chứng được bằng `docker run --rm test-workspace:latest test ! -e /app/.kiro` trả về mã thoát 0.
3. WHEN image được build từ một thư mục làm việc có tệp `.env` THEN THE SYSTEM SHALL không sao chép tệp `.env` vào image, kiểm chứng được bằng `docker run --rm test-workspace:latest test ! -e /app/.env` trả về mã thoát 0.
4. WHEN tệp `.dockerignore` được đọc THEN THE SYSTEM SHALL có các mục `.git`, `.kiro` và `.env` trong tệp này.

### Requirement 4: Script build tiện dụng

**User Story:** Là lập trình viên, tôi muốn có script `scripts/docker-build.sh`, để build image với tên và tag tuỳ chọn mà không cần nhớ tham số của `docker build`.

#### Acceptance Criteria

1. WHEN người dùng chạy `scripts/docker-build.sh` không kèm tham số THEN THE SYSTEM SHALL build image `test-workspace:latest` và kết thúc với mã thoát 0.
2. WHEN người dùng chạy `scripts/docker-build.sh <tag>` với một tag hợp lệ (ví dụ `1.0.0`) THEN THE SYSTEM SHALL build image `test-workspace:<tag>` và kết thúc với mã thoát 0.
3. WHEN biến môi trường `IMAGE_NAME` được đặt khi chạy script THEN THE SYSTEM SHALL dùng giá trị của `IMAGE_NAME` làm tên image thay cho `test-workspace`.
4. WHEN script được chạy từ một thư mục khác thư mục gốc repository THEN THE SYSTEM SHALL vẫn dùng thư mục gốc repository làm build context và build thành công.
5. IF lệnh `docker` không có trong `PATH` THEN THE SYSTEM SHALL in thông báo lỗi chứa chuỗi `docker` ra stderr và kết thúc với mã thoát khác 0.
6. IF `docker build` thất bại THEN THE SYSTEM SHALL kết thúc script với mã thoát khác 0.
7. WHEN người dùng chạy `scripts/docker-build.sh --help` THEN THE SYSTEM SHALL in hướng dẫn sử dụng ra stdout và kết thúc với mã thoát 0 mà không thực hiện build.

### Requirement 5: Tài liệu hướng dẫn

**User Story:** Là thành viên mới của dự án, tôi muốn README có hướng dẫn build Docker image, để có thể tự build và chạy image mà không cần hỏi người khác.

#### Acceptance Criteria

1. WHEN `README.md` được đọc THEN THE SYSTEM SHALL chứa một mục có tiêu đề bao gồm chữ `Docker`.
2. WHEN `README.md` được đọc THEN THE SYSTEM SHALL chứa lệnh `docker build`, lệnh `docker run` và lệnh `scripts/docker-build.sh` làm ví dụ sử dụng.
