#!/bin/bash
set -euo pipefail

trivy=${TRIVY:-ghcr.io/aquasecurity/trivy:0.76.2@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb}
repo=${GITHUB_REPOSITORY:-ingrest-dev/edge}
image=${1:-$(gh release download channels -R "$repo" -p stable.json -O - | jq -r '.images[0].image')}
case "$image" in ghcr.io/ingrest-dev/edge@sha256:*) ;; *) echo "unexpected image '$image'" >&2; exit 1 ;; esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
docker run --rm --network host -e HTTPS_PROXY -e https_proxy -e TRIVY_DISABLE_TELEMETRY=true -e TRIVY_SKIP_VERSION_CHECK=true -v "$work:/out" "$trivy" image --quiet \
	--scanners vuln --pkg-types os --ignore-unfixed --severity HIGH,CRITICAL \
	--format json --output /out/report.json "$image"

rows=$(jq -r '[.Results[]?.Vulnerabilities[]?] | unique_by(.PkgName + .VulnerabilityID) | sort_by(.Severity, .PkgName)[]
	| "| \(.PkgName) | \(.InstalledVersion) | \(.FixedVersion) | [\(.VulnerabilityID)](\(.PrimaryURL // "https://avd.aquasec.com/nvd/" + (.VulnerabilityID | ascii_downcase))) | \(.Severity) |"' "$work/report.json")
[ -n "$rows" ] || exit 0

cat <<EOF
The published image \`$image\` has fixable HIGH or CRITICAL vulnerabilities in Debian packages:

| Package | Installed | Fixed | Vulnerability | Severity |
| --- | --- | --- | --- | --- |
$rows

This pull request changes \`REFRESH\`, so the runtime stage installs current packages instead of its cached layer.
EOF
