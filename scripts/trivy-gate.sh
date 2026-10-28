#!/bin/sh
# Fail if Trivy JSON results contain a fixable HIGH/CRITICAL OS-package vulnerability
# or a fixable CRITICAL one in the Go binaries (scan with --ignore-unfixed). Writes a
# summary per platform to $GITHUB_STEP_SUMMARY when set.
#
# usage: trivy-gate.sh <target> trivy-<platform>.json ...
set -eu

target="${1:?target, e.g. obfs4}"
shift
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
fail=0

for f in "$@"; do
    p="${f##*/}"; p="${p#trivy-}"; p="${p%.json}"
    os_bad="$(jq '[.Results[]? | select(.Class=="os-pkgs")   | .Vulnerabilities[]? | select(.Severity=="HIGH" or .Severity=="CRITICAL")] | length' "$f")"
    lib_crit="$(jq '[.Results[]? | select(.Class=="lang-pkgs") | .Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$f")"
    lib_high="$(jq '[.Results[]? | select(.Class=="lang-pkgs") | .Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "$f")"
    {
        echo "### Trivy: ${target} (${p})"
        echo "- OS packages, HIGH+CRITICAL (fix available): ${os_bad}"
        echo "- Go binaries/libraries, CRITICAL (fix available): ${lib_crit}"
        echo "- Go binaries/libraries, HIGH (reported only): ${lib_high}"
    } >> "$summary"
    if [ "$os_bad" -gt 0 ] || [ "$lib_crit" -gt 0 ]; then
        fail=1
        echo "::error::Gate failed (${p}): os HIGH+CRITICAL=${os_bad}, lib CRITICAL=${lib_crit}"
        jq -r '.Results[]? | .Class as $c | .Vulnerabilities[]?
               | select(($c=="os-pkgs" and (.Severity=="HIGH" or .Severity=="CRITICAL")) or ($c=="lang-pkgs" and .Severity=="CRITICAL"))
               | "\(.VulnerabilityID)\t\(.PkgName)\t\(.InstalledVersion) -> \(.FixedVersion)\t\(.Severity)"' "$f"
    fi
done
exit "$fail"
