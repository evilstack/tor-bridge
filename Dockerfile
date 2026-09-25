# syntax=docker/dockerfile:1
ARG DEBIAN_RELEASE=bookworm
ARG GO_VERSION=1.25

########################################
# Stage: base — common to both images
########################################
FROM debian:${DEBIAN_RELEASE}-slim AS base

ARG DEBIAN_RELEASE
ARG TOR_APT_KEY_FINGERPRINT="A3C4 F0F9 79CA A22C DBA8  F512 EE8C BC9E 886D DD89"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        gnupg \
        curl; \
    curl -fsSL https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc \
        | gpg --dearmor -o /usr/share/keyrings/torproject.gpg; \
    fpr="$(gpg --show-keys --with-fingerprint --with-colons /usr/share/keyrings/torproject.gpg \
        | awk -F: '/^fpr:/ {print $10; exit}')"; \
    expected="$(echo "$TOR_APT_KEY_FINGERPRINT" | tr -d ' ')"; \
    if [ "$fpr" != "$expected" ]; then \
        echo "FATAL: Tor Project apt key fingerprint mismatch!"; \
        echo "  expected: $expected"; \
        echo "  got:      $fpr"; \
        exit 1; \
    fi; \
    echo "Verified Tor Project apt key fingerprint: $fpr"; \
    echo "deb [signed-by=/usr/share/keyrings/torproject.gpg] https://deb.torproject.org/torproject.org ${DEBIAN_RELEASE} main" \
        > /etc/apt/sources.list.d/torproject.list; \
    echo "deb-src [signed-by=/usr/share/keyrings/torproject.gpg] https://deb.torproject.org/torproject.org ${DEBIAN_RELEASE} main" \
        >> /etc/apt/sources.list.d/torproject.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        tor \
        tor-geoipdb \
        deb.torproject.org-keyring; \
    apt-get purge -y --auto-remove gnupg curl; \
    rm -rf /var/lib/apt/lists/*; \
    tor --version

RUN groupadd --system -g 10001 tor-bridge \
    && useradd --system -u 10001 --gid tor-bridge --home-dir /var/lib/tor \
        --shell /usr/sbin/nologin tor-bridge

RUN mkdir -p /var/lib/tor /etc/tor /var/log/tor \
    && chown -R 10001:10001 /var/lib/tor /etc/tor /var/log/tor \
    && chmod 700 /var/lib/tor

USER tor-bridge
WORKDIR /var/lib/tor

HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD test -f /proc/1/status || exit 1

ENTRYPOINT ["tor", "-f", "/etc/tor/torrc"]

########################################
# Stage: lyrebird-builder
########################################
FROM golang:${GO_VERSION}-${DEBIAN_RELEASE} AS lyrebird-builder

ARG LYREBIRD_VERSION=0.8.1

WORKDIR /src
# Copy source fetched by GitHub Actions runner
COPY ./src/lyrebird /src

RUN set -eux; \
    cd /src/cmd/lyrebird; \
    go get github.com/pion/interceptor@v0.1.39; \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.lyrebirdVersion=${LYREBIRD_VERSION}" -o /out/lyrebird; \
    ln -s /usr/bin/lyrebird /out/obfs4proxy

########################################
# Stage: webtunnel-builder
########################################
FROM golang:${GO_VERSION}-${DEBIAN_RELEASE} AS webtunnel-builder

ARG WEBTUNNEL_VERSION=v0.0.5

WORKDIR /src
# Copy source fetched by GitHub Actions runner
COPY ./src/webtunnel /src

RUN set -eux; \
    cd /src/main/server; \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.webtunnelVersion=${WEBTUNNEL_VERSION}" -o /out/webtunnel-server

########################################
# Stage: obfs4 — final runtime image
########################################
FROM base AS obfs4

COPY --link --from=lyrebird-builder /out/ /usr/bin/
COPY --link --chown=10001:10001 torrc.obfs4.example /etc/tor/torrc.example

########################################
# Stage: webtunnel — final runtime image
########################################
FROM base AS webtunnel

COPY --link --from=webtunnel-builder /out/webtunnel-server /usr/bin/webtunnel-server
COPY --link --chown=10001:10001 torrc.webtunnel.example /etc/tor/torrc.example