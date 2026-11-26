#!/bin/bash
set -euo pipefail

trivy=${TRIVY:-ghcr.io/aquasecurity/trivy:0.76.2@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb}
repo=${GITHUB_REPOSITORY:-ingrest-dev/edge}
image=${1:-$(gh release download channels -R "$repo" -p stable.json -O - | jq -r '.images[0].image')}
case "$image" in ghcr.io/ingrest-dev/edge@sha256:*) ;; *) echo "unexpected image '$image'" >&2; exit 1 ;; esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
docker run --rm --entrypoint sh "$image" -c '
	for f in /usr/local/nginx/sbin/nginx /usr/local/nginx/modules/*.so /usr/local/modsecurity/lib/*.so.* /usr/local/luajit/lib/*.so.*; do
		[ -e "$f" ] && ldd "$f"
	done | awk "\$2 == \"=>\" && \$3 ~ /^\// {print \$3}" | sort -u | while read -r lib; do
		dpkg -S "$lib" 2>/dev/null || dpkg -S "$(readlink -f "$lib")" 2>/dev/null || true
	done | cut -d: -f1 | sort -u' >"$work/linked.txt"
[ -s "$work/linked.txt" ] || { echo "no linked Debian packages found in $image" >&2; exit 1; }

docker run --rm --network host -e HTTPS_PROXY -e https_proxy -e TRIVY_DISABLE_TELEMETRY=true -e TRIVY_SKIP_VERSION_CHECK=true -v "$work:/out" "$trivy" image --quiet \
	--scanners vuln --pkg-types os --severity HIGH,CRITICAL --format json --output /out/report.json "$image"

ignore=$(dirname "$0")/unfixed.ignore
rows=$(jq -r --rawfile linked "$work/linked.txt" --rawfile ignored "$ignore" '($linked | split("\n") | map(select(. != ""))) as $pkgs
	| ($ignored | split("\n") | map(split(" ")[0] | select(. != ""))) as $skip
	| [.Results[]?.Vulnerabilities[]? | select((.FixedVersion // "") == "" and (.PkgName as $p | $pkgs | index($p)) and (.VulnerabilityID as $v | $skip | index($v) | not))]
	| unique_by(.PkgName + .VulnerabilityID) | sort_by(.Severity, .PkgName, .VulnerabilityID)[]
	| "| \(.PkgName) | \(.InstalledVersion) | [\(.VulnerabilityID)](\(.PrimaryURL // "https://avd.aquasec.com/nvd/" + (.VulnerabilityID | ascii_downcase))) | \(.Severity) | \((.Title // "") | gsub("[|\n]"; " ") | .[:100]) |"' "$work/report.json")
[ -n "$rows" ] || exit 0

cat <<BODY
The published image \`$image\` links Debian packages with HIGH or CRITICAL vulnerabilities that Debian has not fixed yet:

| Package | Installed | Vulnerability | Severity | Title |
| --- | --- | --- | --- | --- |
$rows

A \`REFRESH\` pull request cannot help until Debian ships a fix. Check whether the code nginx uses is affected:

- not affected: add the id with the reason to \`tools/watch/unfixed.ignore\`;
- affected, with an upstream release that fixes it: build that library from source in the \`Dockerfile\` (as \`libmodsecurity\`) and add it to \`tools/watch/modules.sh\`.

Linked packages: $(paste -sd' ' "$work/linked.txt")
BODY
