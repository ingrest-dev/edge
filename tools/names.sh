#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
found=$(git ls-files -z | grep -zv '^tools/names\.sh$' | xargs -0 grep -n -i -I -H 'openresty' \
	| sed -E 's#github\.com/openresty/[A-Za-z0-9_.-]+##g; s#openresty/[A-Za-z0-9_.-]+##g' \
	| grep -i 'openresty' || true)
if [ -n "$found" ]; then
	echo "the old product name is only allowed in module source paths:"
	echo "$found"
	exit 1
fi
