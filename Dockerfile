FROM alpine:3.20

LABEL org.opencontainers.image.title="test-workspace"

WORKDIR /app

RUN addgroup -S app && adduser -S -G app app

COPY --chown=app:app . /app

USER app

CMD ["ls", "-la", "/app"]
