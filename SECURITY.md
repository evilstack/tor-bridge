# Security policy

This is a hobby project (see the [README](README.md)): I maintain it in my spare time, so there is
no SLA. I do take security seriously, because people may run these images in front of bridges that
help others reach the Tor network.

## Supported versions

Only the newest published builds are supported: the `latest` tags and the newest
`lyrebird-<version>` / `webtunnel-<version>` tags of each image. Older tags are not patched; they
are replaced by rebuilds, which happen automatically when Tor, the transport or the base image
changes. Please update rather than asking for fixes to an old tag.

## Reporting a vulnerability

Please report privately:

1. Use **Security → Report a vulnerability** on this repository (GitHub private vulnerability
   reporting).
2. If that option isn't available, open an issue that says you have a security report and leaves
   out the details, and I'll arrange a private channel.

Please include the image and tag (ideally the digest), what you found, how to reproduce it, and
the impact you expect.

I'll aim to acknowledge reports within about a week and to keep you updated as I work on a fix.
I'm happy to credit you in the advisory unless you'd rather stay anonymous.

## What's in scope

- The Dockerfile, scripts, and the CI/CD workflows in this repository
- The published images' packaging: file permissions, the runtime user, how packages are sourced
  and verified, and the signatures, provenance and SBOMs attached to the images
- Anything that could let someone tamper with the build or publish pipeline, or that exposes
  secrets used by it

## What's out of scope

- Vulnerabilities in Tor, lyrebird, WebTunnel or Debian packages themselves. Please report those
  to the Tor Project (start at <https://www.torproject.org/contact/>) or to Debian. These images
  pick up fixes by rebuilding once fixed packages are published.
- Vulnerabilities that have no fix available yet. The pipeline reports fixable HIGH and CRITICAL
  findings (and blocks publishing on them) and shows results in this repository's Security tab.
- Advice on operating a bridge safely (hosting, anonymity, legal questions).

## Verifying what you pull

Images are signed with Sigstore and carry build provenance and an SBOM. How to check them is in
the [README](README.md#verifying-what-you-pull). If an image doesn't verify, or the signature
identity isn't this repository's workflow on `main`, treat it as a security problem and report it.
