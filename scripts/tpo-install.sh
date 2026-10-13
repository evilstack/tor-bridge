#!/bin/sh
# Install packages from the Tor Project apt repository (deb.torproject.org),
# optionally pinned to exact versions, and fail the build if any requested
# package would come from somewhere else (e.g. the Debian archive).
#
# usage: tpo-install.sh name[=version] ...
set -eu
export DEBIAN_FRONTEND=noninteractive

apt-get update

for spec in "$@"; do
    name="${spec%%=*}"
    # --print-uris lists what apt would download; the requested package itself
    # must be served by deb.torproject.org.
    if ! apt-get install --print-uris -qq --no-install-recommends "$spec" \
        | grep -Eq "^'https://deb\.torproject\.org/[^']*/${name}_"; then
        echo "FATAL: ${spec} does not resolve to deb.torproject.org" >&2
        exit 1
    fi
done

apt-get install -y --no-install-recommends "$@"
rm -rf /var/lib/apt/lists/*
