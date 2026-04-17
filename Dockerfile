# Dockerfile for BibTime — self-hosted race timing platform
# Multi-stage build: deps → compile → assets → release → runtime

ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.3
ARG DEBIAN_VERSION=bookworm-20250317-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# ── Stage 1: deps ──────────────────────────────────────────────────
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

# Install dependencies first (cached layer)
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# ── Stage 2: compile & assets ──────────────────────────────────────
COPY priv priv
COPY lib lib
COPY assets assets

# Compile assets
RUN mix assets.deploy

# Compile application
COPY config/runtime.exs config/
RUN mix compile

# ── Stage 3: release ──────────────────────────────────────────────
COPY rel rel
RUN mix release

# ── Stage 4: runtime ──────────────────────────────────────────────
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates sqlite3 curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install Litestream for continuous SQLite backups to object storage.
ARG LITESTREAM_VERSION=0.3.13
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    curl -fsSL -o /tmp/litestream.tar.gz \
      "https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/litestream-v${LITESTREAM_VERSION}-linux-${arch}.tar.gz"; \
    tar -C /usr/local/bin -xzf /tmp/litestream.tar.gz; \
    rm /tmp/litestream.tar.gz; \
    litestream version

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

ENV MIX_ENV="prod"

# Only copy the release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/bibtime ./

# Litestream reads /etc/litestream.yml by default; env vars are interpolated at runtime.
COPY litestream.yml /etc/litestream.yml

# Create data directory for SQLite database
RUN mkdir -p /data && chown nobody:root /data

USER nobody

ENV DATABASE_PATH=/data/bibtime.db
ENV PHX_SERVER=true
ENV PORT=8080

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:8080/healthz || exit 1

CMD ["bin/docker-entrypoint"]
