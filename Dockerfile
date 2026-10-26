# syntax=docker/dockerfile:1
#
# Tor bridge images built ONLY from Tor Project packages (deb.torproject.org):
#   --target obfs4       tor + lyrebird          (obfs4 server transport)
#   --target webtunnel   tor + webtunnel-server  (WebTunnel server transport)
#
# Always pass --target; there is intentionally no default image.
#
# Build args TOR_VERSION / LYREBIRD_VERSION / WEBTUNNEL_VERSION are optional.
# CI resolves the current versions (see the `versions` stage) and passes them so
# the cache is invalidated exactly when a package changes. Without them a local
# `docker build` simply installs the newest available packages.

########################################
# apt-base: Tor Project apt repo, key fingerprint verified
########################################
FROM debian:trixie-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad AS apt-base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TOR_APT_FINGERPRINT="A3C4 F0F9 79CA A22C DBA8  F512 EE8C BC9E 886D DD89"

# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg; \
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 \
        https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc \
        | gpg --dearmor -o /usr/share/keyrings/torproject.gpg; \
    # Exactly one primary key, and it must be the expected one.
    keys="$(gpg --show-keys --with-colons /usr/share/keyrings/torproject.gpg)"; \
    [ "$(echo "$keys" | grep -c '^pub:')" = 1 ] || { echo "FATAL: expected exactly one primary key"; exit 1; }; \
    fpr="$(echo "$keys" | awk -F: '/^fpr:/ {print $10; exit}')"; \
    expected="$(echo "$TOR_APT_FINGERPRINT" | tr -d ' ')"; \
    if [ "$fpr" != "$expected" ]; then \
        echo "FATAL: Tor Project apt key fingerprint mismatch!"; \
        echo "  expected: $expected"; \
        echo "  got:      $fpr"; \
        exit 1; \
    fi; \
    echo "Verified Tor Project apt key fingerprint: $fpr"; \
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"; \
    echo "deb [signed-by=/usr/share/keyrings/torproject.gpg] https://deb.torproject.org/torproject.org ${codename} main" \
        > /etc/apt/sources.list.d/torproject.list; \
    # Prefer the Tor Project build of these packages over any Debian-archive copy.
    printf 'Package: tor tor-geoipdb lyrebird webtunnel\nPin: origin deb.torproject.org\nPin-Priority: 900\n' \
        > /etc/apt/preferences.d/torproject; \
    apt-get purge -y --auto-remove curl gnupg; \
    rm -rf /var/lib/apt/lists/*

########################################
# versions: resolve the current candidate versions (CI helper, not an image)
#   docker buildx build --target versions --no-cache-filter resolve \
#       --output type=local,dest=./versions-out .
# writes ./versions-out/versions.env
########################################
FROM apt-base AS resolve
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# throwaway stage: apt lists are intentionally not cleaned
# hadolint ignore=DL3009
RUN set -eux; \
    apt-get update; \
    for p in tor lyrebird webtunnel; do \
        v="$(apt-cache policy "$p" | awk '/^  Candidate:/ {print $2}')"; \
        if [ -z "$v" ] || [ "$v" = "(none)" ]; then \
            echo "FATAL: no install candidate for $p" >&2; exit 1; \
        fi; \
        printf '%s_VERSION=%s\n' "$(echo "$p" | tr '[:lower:]' '[:upper:]')" "$v"; \
    done > /versions.env; \
    cat /versions.env

FROM scratch AS versions
COPY --from=resolve /versions.env /versions.env

########################################
# runtime-base: tor + unprivileged user, common to both images
########################################
FROM apt-base AS runtime-base

ARG TOR_VERSION

RUN --mount=type=bind,source=scripts/tpo-install.sh,target=/tmp/tpo-install.sh \
    set -eux; \
    sh /tmp/tpo-install.sh "tor${TOR_VERSION:+=${TOR_VERSION}}" tor-geoipdb; \
    tor --version

RUN groupadd --system -g 10001 tor-bridge \
    && useradd --system -u 10001 --gid tor-bridge --home-dir /var/lib/tor \
        --shell /usr/sbin/nologin tor-bridge \
    && install -d -m 700 -o 10001 -g 10001 /var/lib/tor \
    && install -d -m 755 -o 10001 -g 10001 /var/log/tor
# /etc/tor stays root-owned: the runtime user can read its config but not change it.

# Packaging license and third-party notices travel with every image.
COPY --link LICENSE NOTICE /usr/share/doc/tor-bridge/

USER tor-bridge
WORKDIR /var/lib/tor

# No HEALTHCHECK on purpose: the previous `test -f /proc/1/status` was always true
# and reported "healthy" for bridges that never bootstrapped.

ENTRYPOINT ["tor", "-f", "/etc/tor/torrc"]

########################################
# obfs4: final runtime image
########################################
FROM runtime-base AS obfs4

ARG LYREBIRD_VERSION

USER root
RUN --mount=type=bind,source=scripts/tpo-install.sh,target=/tmp/tpo-install.sh \
    set -eux; \
    sh /tmp/tpo-install.sh "lyrebird${LYREBIRD_VERSION:+=${LYREBIRD_VERSION}}"; \
    test -x /usr/bin/lyrebird
COPY --link torrc.obfs4.example /etc/tor/torrc.example
# Upstream license files for the packaged release (see scripts/fetch-upstream-licenses.sh).
COPY --link licenses/lyrebird/ /usr/share/doc/tor-bridge/licenses/lyrebird/
USER tor-bridge

LABEL org.opencontainers.image.title="Tor obfs4 bridge" \
      org.opencontainers.image.description="Unofficial Tor bridge image: Tor Project tor + lyrebird (obfs4), built from deb.torproject.org packages" \
      org.opencontainers.image.source="https://github.com/evilstack/tor-bridge" \
      org.opencontainers.image.base.name="docker.io/library/debian:trixie-slim"

########################################
# webtunnel: final runtime image
########################################
FROM runtime-base AS webtunnel

ARG WEBTUNNEL_VERSION

USER root
# The webtunnel package also ships webtunnel-client, which a bridge never runs:
# have dpkg skip it so the image (and its scan results) only contain what runs.
RUN --mount=type=bind,source=scripts/tpo-install.sh,target=/tmp/tpo-install.sh \
    set -eux; \
    echo 'path-exclude=/usr/bin/webtunnel-client' > /etc/dpkg/dpkg.cfg.d/99-no-webtunnel-client; \
    sh /tmp/tpo-install.sh "webtunnel${WEBTUNNEL_VERSION:+=${WEBTUNNEL_VERSION}}"; \
    rm -f /etc/dpkg/dpkg.cfg.d/99-no-webtunnel-client; \
    test -x /usr/bin/webtunnel-server; \
    [ ! -e /usr/bin/webtunnel-client ]
COPY --link torrc.webtunnel.example /etc/tor/torrc.example
# Upstream license files for the packaged release (see scripts/fetch-upstream-licenses.sh).
COPY --link licenses/webtunnel/ /usr/share/doc/tor-bridge/licenses/webtunnel/
USER tor-bridge

LABEL org.opencontainers.image.title="Tor WebTunnel bridge" \
      org.opencontainers.image.description="Unofficial Tor bridge image: Tor Project tor + webtunnel-server, built from deb.torproject.org packages" \
      org.opencontainers.image.source="https://github.com/evilstack/tor-bridge" \
      org.opencontainers.image.base.name="docker.io/library/debian:trixie-slim"
