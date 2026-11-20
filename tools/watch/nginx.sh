#!/bin/bash
set -euo pipefail

current=$(sed 's/\.[0-9]*$//' VERSION)
latest=$(curl -fsSL --retry 5 https://nginx.org/en/download.html | sed -n 's/.*Mainline version\(.*\)Stable version.*/\1/p' | grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' | head -n 1 | sed 's/^nginx-//; s/\.tar\.gz$//')
[ -n "$latest" ] || { echo "no mainline version on nginx.org" >&2; exit 1; }
[ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n 1)" != "$current" ] || exit 0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL --retry 5 -o "$work/nginx.tar.gz" "https://nginx.org/download/nginx-$latest.tar.gz"
curl -fsSL --retry 5 -o "$work/nginx.tar.gz.asc" "https://nginx.org/download/nginx-$latest.tar.gz.asc" || { echo "nginx $latest has no signature yet" >&2; exit 0; }
gpgv --keyring "$PWD/keys/nginx.gpg" "$work/nginx.tar.gz.asc" "$work/nginx.tar.gz" >&2

changes=$(curl -fsSL --retry 5 https://nginx.org/en/CHANGES | awk -v v="$latest" '
	/^Changes with nginx / { on = ($4 == v) ; next }
	on { print }')
security=$(printf '%s\n' "$changes" | awk '
	/^ *\*\) / { if (item != "") print item; item = ""; sec = ($2 == "Security:") }
	sec { sub(/^ +/, ""); item = item (item == "" ? "" : " ") $0 }
	/^$/ { if (item != "") print item; item = ""; sec = 0 }
	END { if (item != "") print item }')

echo "version=$latest"
if [ -n "$security" ]; then
	echo "security=true"
else
	echo "security=false"
fi
{
	echo "nginx $latest, signature checked against \`keys/nginx.gpg\`."
	if [ -n "$security" ]; then
		echo
		echo "Security fixes from the nginx CHANGES:"
		echo
		printf '%s\n' "$security" | sed 's/^\*) /- /'
	fi
} >"${BODY:-/dev/stderr}"
