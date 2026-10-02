FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
RUN apk add --no-cache rsync bash && \
    adduser -D -u 1001 appuser
WORKDIR /app
# At CI time we COPY the composed .build/<site>/wp-content
COPY .build/__SITE__/wp-content /app/wp-content
USER appuser
