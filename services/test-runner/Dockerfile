FROM alpine:3.20

RUN apk add --no-cache \
    bash \
    curl \
    jq \
    redis

WORKDIR /tests

COPY tests/ ./tests/

RUN chmod +x tests/*.sh tests/lib/*.sh

ENTRYPOINT ["bash", "tests/run_all.sh"]
