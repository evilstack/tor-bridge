# syntax=docker/dockerfile:1
ARG DEBIAN_RELEASE=bookworm
ARG LYREBIRD_VERSION=0.8.1
ARG WEBTUNNEL_VERSION=v0.0.5

########################################
# Stage: base — common to both images
########################################
FROM debian:${DEBIAN_RELEASE}-slim AS base

# Inherit global ARG without overriding default
ARG DEBIAN_RELEASE

ARG TOR_APT_KEY_FINGERPRINT="A3C4 F0F9 79CA A22C DBA8  F512 EE8C BC9E 886D DD89"

# Combine tool install, key verification, repo setup, tor install, and cleanup into one layer
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

# Dedicated system user with explicit UID/GID for predictable persistent permissions
RUN groupadd --system -g 10001 tor-bridge \
    && useradd --system -u 10001 --gid tor-bridge --home-dir /var/lib/tor \
        --shell /usr/sbin/nologin tor-bridge

RUN mkdir -p /var/lib/tor /etc/tor /var/log/tor \
    && chown -R tor-bridge:tor-bridge /var/lib/tor /etc/tor /var/log/tor \
    && chmod 700 /var/lib/tor

USER tor-bridge
WORKDIR /var/lib/tor

# Direct status check without relying on procps / pgrep
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD test -f /proc/1/status || exit 1

ENTRYPOINT ["tor", "-f", "/etc/tor/torrc"]

########################################
# Stage: lyrebird-builder — compiles transport executable
########################################
FROM golang:1.22-${DEBIAN_RELEASE} AS lyrebird-builder

ARG LYREBIRD_VERSION=0.8.1

RUN set -eux; \
    git clone --depth 1 --branch lyrebird-${LYREBIRD_VERSION} https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird.git /src; \
    cd /src/cmd/lyrebird; \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.lyrebirdVersion=${LYREBIRD_VERSION}" -o /out/lyrebird

RUN ln -s /usr/bin/lyrebird /out/obfs4proxy
    
########################################
# Stage: webtunnel-builder — compiles transport executable
########################################
FROM golang:1.22-${DEBIAN_RELEASE} AS webtunnel-builder

ARG WEBTUNNEL_VERSION=v0.0.5

RUN set -eux; \
    git clone --depth 1 --branch ${WEBTUNNEL_VERSION} https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/webtunnel.git /src; \
    cd /src/main/server; \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.webtunnelVersion=${WEBTUNNEL_VERSION}" -o /out/webtunnel-server

########################################
# Stage: obfs4 — final runtime image
########################################
FROM base AS obfs4

# Copy lyrebird binary, and symlink for torrc configurations calling obfs4proxy
COPY --link --from=lyrebird-builder /out/ /usr/bin/

COPY --chown=tor-bridge:tor-bridge torrc.obfs4.example /etc/tor/torrc.example

########################################
# Stage: webtunnel — final runtime image
########################################
FROM base AS webtunnel

COPY --from=webtunnel-builder /out/webtunnel-server /usr/bin/webtunnel-server

COPY --chown=tor-bridge:tor-bridge torrc.webtunnel.example /etc/tor/torrc.example
