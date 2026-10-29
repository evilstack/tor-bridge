# tor-bridge

Personal, unofficial Docker images for running a Tor **obfs4** or **WebTunnel** bridge.

[![CI Checks](https://github.com/evilstack/tor-bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/evilstack/tor-bridge/actions/workflows/ci.yml)
[![Build & Publish](https://github.com/evilstack/tor-bridge/actions/workflows/build-and-push.yml/badge.svg)](https://github.com/evilstack/tor-bridge/actions/workflows/build-and-push.yml)
[![GHCR](https://img.shields.io/badge/Registry-GHCR.io-blue?logo=docker&logoColor=white)](https://github.com/evilstack/tor-bridge/pkgs/container/tor-bridge%2Ftor-obfs4)
[![Tor Version](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/evilstack/5aed119df3ac047fb3e06085fe0bcfb7/raw/tor-version.json)](https://www.torproject.org/)
[![Base OS](https://img.shields.io/badge/Base-Debian_Trixie-D70A53?logo=debian&logoColor=white)](https://www.debian.org/)
[![License](https://img.shields.io/github/license/evilstack/tor-bridge)](LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/evilstack/tor-bridge/badge)](https://scorecard.dev/viewer/?uri=github.com/evilstack/tor-bridge)

> **This is a hobby project.** I run my own Tor bridges and wanted new Tor, lyrebird and WebTunnel
> releases sooner than I was getting them from the official images. It's also a good excuse to
> mess around with image builds and release pipelines: signing, SBOMs, provenance, vulnerability
> scanning and automated updates. The images work for me and you're welcome to use them, but
> there's no support guarantee and no promise I'll keep this going forever. If you want the
> officially supported route, use the Tor Project's own bridge images and documentation.
>
> Not affiliated with or endorsed by The Tor Project, Inc. "Tor" and the Tor logo are trademarks
> of The Tor Project, Inc., used here only to say what the images are for.

## Images

| Image | Contains | Transport binary |
|---|---|---|
| `ghcr.io/evilstack/tor-bridge/tor-obfs4` | `tor` + `lyrebird` | `/usr/bin/lyrebird` |
| `ghcr.io/evilstack/tor-bridge/tor-webtunnel` | `tor` + `webtunnel` (server only) | `/usr/bin/webtunnel-server` |

Platforms: `linux/amd64` and `linux/arm64`.

Tags (shown for obfs4; WebTunnel images use `webtunnel-…`):

| Tag | Meaning |
|---|---|
| `latest` | newest build from `main` |
| `lyrebird-<version>` | newest build with that lyrebird release |
| `lyrebird-<version>-tor<version>` | that lyrebird release with that Tor release |
| `sha-<commit>` | the build from that commit |

Tags move whenever Tor, the transport, or the base image updates. **For anything you care about,
pin by digest** (`image@sha256:…`) and update on purpose.

## What's inside

- Debian `trixie-slim` base.
- `tor`, `tor-geoipdb` and the transport, installed straight from the Tor Project's apt repository
  (`deb.torproject.org`). **Nothing is compiled here.** The repository's signing key fingerprint is
  pinned in the [Dockerfile](Dockerfile), and the build fails if a package would come from anywhere
  else (for example the Debian archive).
- Runs as an unprivileged user (UID/GID `10001`). `/etc/tor` is root-owned, so the process can read
  its config but not change it. Bridge state (including the bridge identity keys) lives in
  `/var/lib/tor`: keep that on a volume, or you get a new bridge identity on every recreate.
- License and notice files in `/usr/share/doc/tor-bridge/`.
- An example config at `/etc/tor/torrc.example` (same as `torrc.obfs4.example` /
  `torrc.webtunnel.example` in this repo).
- No `HEALTHCHECK`. I'd rather have none than one that always says "healthy".

## Running

You supply the `torrc`. Start from the example for your transport. The transport lines are:

```
# obfs4
ServerTransportPlugin obfs4 exec /usr/bin/lyrebird

# WebTunnel
ServerTransportPlugin webtunnel exec /usr/bin/webtunnel-server
```

```bash
docker run -d --name tor-obfs4 --restart unless-stopped \
  --cap-drop ALL --security-opt no-new-privileges \
  -v "$PWD/torrc:/etc/tor/torrc:ro" \
  -v tor-obfs4-data:/var/lib/tor \
  -p <port>:<port>/tcp \
  ghcr.io/evilstack/tor-bridge/tor-obfs4:latest
```

Notes:

- Publish whatever port your `torrc` makes the transport listen on.
- A named volume picks up the right ownership automatically. For a bind mount, `chown 10001:10001`
  the directory first.
- WebTunnel is meant to sit behind a TLS-terminating reverse proxy on a real domain. See the Tor
  Project's [bridge setup guides](https://community.torproject.org/relay/setup/) for the full
  picture; this image only provides the server binary.

## Verifying what you pull

Every published image is signed and has build provenance. Replace the tag with a digest if you
pinned one.

```bash
IMAGE=ghcr.io/evilstack/tor-bridge/tor-obfs4:latest

# Signature (keyless, Sigstore): proves it was built by this repository's workflow on main
cosign verify "$IMAGE" \
  --certificate-identity-regexp '^https://github.com/evilstack/tor-bridge/\.github/workflows/build-and-push\.yml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

# GitHub build provenance attestation
gh attestation verify "oci://$IMAGE" --repo evilstack/tor-bridge

# SBOM and BuildKit provenance embedded in the image index
docker buildx imagetools inspect "$IMAGE" --format '{{ json .SBOM }}'
docker buildx imagetools inspect "$IMAGE" --format '{{ json .Provenance }}'
```

Image labels record what went in: `org.opencontainers.image.revision`, the Tor and transport
package versions, and the base image digest.

## How it's built

[`build-and-push.yml`](.github/workflows/build-and-push.yml), roughly:

1. **Daily** (and on every push/PR): ask the Tor Project apt repo which `tor`, `lyrebird` and
   `webtunnel` versions are current, and fingerprint every package version the images would
   contain (so Debian security updates to any dependency count too). A scheduled run only
   rebuilds an image if its inputs (package versions, package fingerprint, base image digest,
   commit) differ from what's published, so a build on `main` that didn't publish is retried.
   Images get `apt-get upgrade`d, so Debian security fixes don't wait for a new base image.
2. **Build once** per image, for both architectures (arm64 under QEMU), with SBOM and
   max-detail provenance. On `main` it's pushed by digest only: no tags yet.
3. **Smoke-test and scan that exact digest**: run the amd64 image (unprivileged user, read-only
   config, tor must launch the transport), then scan it with [Trivy](https://trivy.dev).
   Results go to this repo's Security tab (SARIF). The build fails on any fixable HIGH/CRITICAL
   OS vulnerability or fixable CRITICAL one in the Go binaries.
4. **Publish** only if every scan passed: tag the scanned digest, sign it with cosign, attest
   provenance, then verify its own signature before finishing.

[`rescan.yml`](.github/workflows/rescan.yml) re-scans the published `latest` images daily with a
fresh vulnerability database, so anything disclosed after publishing shows up in the Security tab.

The rest of the safety net: all actions pinned by commit SHA, least-privilege tokens per job,
[Dependabot](.github/dependabot.yml) for actions and the base image, and
[CI checks](.github/workflows/ci.yml) (actionlint, zizmor, Hadolint, ShellCheck, dependency review).

## Building locally

```bash
docker buildx build --target obfs4 -t tor-obfs4:dev .        # newest packages
docker buildx build --target webtunnel -t tor-webtunnel:dev .

# run it like CI does: user/permission checks, then tor must launch the transport
# (the test bridge never publishes a descriptor)
bash scripts/smoke-test.sh tor-obfs4:dev obfs4

# which package versions would CI use right now?
docker buildx build --target versions --no-cache-filter resolve --output type=local,dest=./out .
cat out/versions.env
```

Optional build args `TOR_VERSION`, `LYREBIRD_VERSION` and `WEBTUNNEL_VERSION` pin exact package
versions.

## Credits and licensing

- This repository's own files (Dockerfile, workflows, scripts, docs) are under the
  [MIT License](LICENSE). That covers the packaging only, **not** the software inside the images.
- The images contain other people's software under their own licenses:

  | Component | In | License | Upstream |
  |---|---|---|---|
  | Tor | both | BSD-3-Clause (the upstream license file also covers some bundled third-party code) | [The Tor Project](https://gitlab.torproject.org/tpo/core/tor) |
  | Lyrebird | obfs4 | GPL-3.0-or-later overall, with parts under BSD-2-Clause | [The Tor Project](https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird); continues Yawning Angel's `obfs4proxy` |
  | WebTunnel | webtunnel | MIT | [The Tor Project](https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/webtunnel) |
  | Debian base and packages | both | various (per package) | [Debian](https://www.debian.org/) |

  Details, copyright holders, where the license texts live inside each image
  (`/usr/share/doc/tor-bridge/`), and where to get the source are in [NOTICE](NOTICE).
- The `org.opencontainers.image.licenses` label lists the principal software (Tor plus the
  transport); Debian's base packages are not enumerated there.
- My part is the packaging: the Dockerfile, the version resolution, and the build/scan/sign
  pipeline. The software itself is entirely upstream's work. Thank you to the Tor Project's
  anti-censorship team for building it.

## Feedback

Issues and suggestions are welcome, with the hobby-project caveat above. Security problems in the
packaging or pipeline: see [SECURITY.md](SECURITY.md). Problems with Tor, lyrebird or WebTunnel
themselves belong with the [Tor Project](https://support.torproject.org/).
