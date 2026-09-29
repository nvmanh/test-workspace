# Agent Test

## Docker

Build image trực tiếp:

```sh
docker build -t test-workspace:latest .
```

Hoặc dùng script (tag mặc định `latest`, tên image đổi được qua `IMAGE_NAME`):

```sh
scripts/docker-build.sh
scripts/docker-build.sh 1.0.0
IMAGE_NAME=my-image scripts/docker-build.sh 1.0.0
scripts/docker-build.sh --help
```

Chạy container:

```sh
docker run --rm test-workspace:latest
```
