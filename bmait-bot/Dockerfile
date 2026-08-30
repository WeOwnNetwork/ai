# b.MAIT.bot — Hermes Agent + buzz CLI (needed for the Buzz adapter).
# Hermes image does not ship `buzz`; outbound and adapter load require it on PATH.

ARG BUZZ_GIT_SHA=6df7eba24d49b6a2c7f0188b19e24f3df999678c

FROM rust:1.88-bookworm@sha256:af306cfa71d987911a781c37b59d7d67d934f49684058f96cf72079c3626bfe0 AS buzzcli
ARG BUZZ_GIT_SHA
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
	&& rm -rf /var/lib/apt/lists/*
WORKDIR /src
# Same git pin as docs/PRJ-432.2-buzz-deployment.md (relay this bot talks to).
RUN git clone --filter=blob:none https://github.com/block/buzz.git . \
	&& git checkout "${BUZZ_GIT_SHA}"
RUN cargo build --release -p buzz-cli \
	&& install -m 0755 target/release/buzz /buzz

FROM nousresearch/hermes-agent:latest@sha256:e4fca5593bc885c17ecadb406358ec4e5a5539737b06d8192108c2e22ca15e2d
COPY --from=buzzcli /buzz /usr/local/bin/buzz
