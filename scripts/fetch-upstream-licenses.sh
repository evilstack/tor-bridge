#!/usr/bin/env bash
# Copy the upstream license files for the packaged lyrebird / webtunnel releases into licenses/.
# They are installed into the images (see Dockerfile) and referenced from NOTICE.
#
# usage: scripts/fetch-upstream-licenses.sh <lyrebird-version> <webtunnel-version>
#   e.g. scripts/fetch-upstream-licenses.sh 0.9.0 0.0.7
#
# Tags follow the upstream convention used by this project's earlier source builds:
#   lyrebird-<version>   and   v<version>
# Re-run after a release changes the license files, then review `git diff licenses/`.
set -euo pipefail

lyrebird_version="${1:?lyrebird upstream version, e.g. 0.9.0}"
webtunnel_version="${2:?webtunnel upstream version, e.g. 0.0.7}"

base="https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch() { # <name> <git tag>
    local name="$1" tag="$2" dest="$root/licenses/$1" commit
    git clone --quiet --depth 1 --branch "$tag" "${base}/${name}.git" "$tmp/${name}"
    commit="$(git -C "$tmp/${name}" rev-parse HEAD)"
    rm -rf "$dest"
    mkdir -p "$dest"
    find "$tmp/${name}" -maxdepth 1 -type f \
        \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' \) -exec cp {} "$dest/" \;
    if [ -z "$(ls -A "$dest")" ]; then
        echo "error: no license files found in ${name} ${tag}" >&2
        exit 1
    fi
    printf '%s %s %s\n' "$name" "$tag" "$commit" >> "$tmp/sources.txt"
    echo "${name} ${tag} (${commit}):"
    ls -1 "$dest" | sed 's/^/  /'
}

: > "$tmp/sources.txt"
fetch lyrebird "${lyrebird_version}"
fetch webtunnel "v${webtunnel_version}"

{
    echo "# Upstream releases the files in this directory were copied from (scripts/fetch-upstream-licenses.sh)"
    cat "$tmp/sources.txt"
} > "$root/licenses/SOURCES.txt"
