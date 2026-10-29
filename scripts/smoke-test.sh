#!/bin/bash
# Run a built image the way the README says to and check that it works: unprivileged user,
# read-only /etc/tor, writable /var/lib/tor, and tor actually launching the pluggable
# transport. The bridge never publishes a descriptor, so nothing is announced to the network.
#
# usage: smoke-test.sh <image> <obfs4|webtunnel>
set -euo pipefail

image="${1:?image reference, e.g. tor-obfs4:dev}"
target="${2:?target: obfs4 or webtunnel}"

case "$target" in
    obfs4)
        pt=obfs4
        bin=/usr/bin/lyrebird
        pt_lines="ServerTransportListenAddr obfs4 127.0.0.1:9002"
        ;;
    webtunnel)
        pt=webtunnel
        bin=/usr/bin/webtunnel-server
        pt_lines="ServerTransportListenAddr webtunnel 127.0.0.1:15000
ServerTransportOptions webtunnel url=https://smoke-test.invalid/smoke"
        ;;
    *) echo "unknown target: $target" >&2; exit 2 ;;
esac

fail() { echo "FAIL: $*" >&2; exit 1; }
in_image() { docker run --rm --entrypoint "$1" "$image" "${@:2}"; }

echo "== runtime user and permissions"
[ "$(in_image id -u)" = 10001 ] || fail "not running as UID 10001"
[ "$(in_image id -g)" = 10001 ] || fail "not running as GID 10001"
in_image sh -c 'test ! -w /etc/tor' || fail "/etc/tor is writable by the runtime user"
# shellcheck disable=SC2016 # expands inside the container
in_image sh -c 'test -w /var/lib/tor && [ "$(stat -c %a /var/lib/tor)" = 700 ]' \
    || fail "/var/lib/tor is not a private, writable data directory"
in_image test -x "$bin" || fail "$bin missing"
if [ "$target" = webtunnel ]; then
    in_image sh -c 'test ! -e /usr/bin/webtunnel-client' || fail "webtunnel-client is installed"
fi

echo "== tor launches the ${pt} transport"
tmp="$(mktemp -d)"
name="tor-smoke-${target}-$$"
# shellcheck disable=SC2329 # invoked by the trap
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT

cat > "$tmp/torrc" <<EOF
BridgeRelay 1
PublishServerDescriptor 0
BridgeDistribution none
AssumeReachable 1
SocksPort 0
ORPort 127.0.0.1:auto
ExtORPort auto
DataDirectory /var/lib/tor
Log notice stdout
Nickname smoketest
ServerTransportPlugin ${pt} exec ${bin}
${pt_lines}
EOF
# Readable by UID 10001 inside the container.
chmod 755 "$tmp"
chmod 644 "$tmp/torrc"

docker run -d --name "$name" --cap-drop ALL --security-opt no-new-privileges \
    -v "$tmp/torrc:/etc/tor/torrc:ro" "$image" >/dev/null

for _ in $(seq 60); do
    if docker logs "$name" 2>&1 | grep -q "Registered server transport '${pt}'"; then
        docker logs "$name" 2>&1 | grep "Registered server transport"
        echo "OK: ${image} (${target})"
        exit 0
    fi
    if [ "$(docker inspect -f '{{.State.Running}}' "$name")" != true ]; then
        docker logs "$name" >&2 || true
        fail "tor exited before registering the ${pt} transport"
    fi
    sleep 1
done
docker logs "$name" >&2 || true
fail "tor did not register the ${pt} transport within 60s"
