FROM alpine:3.20
RUN apk add --no-cache rsync bash && \
    adduser -D -u 1001 appuser
WORKDIR /app
# At CI time we COPY the composed .build/<site>/wp-content
COPY .build/__SITE__/wp-content /app/wp-content
USER appuser
