#!/bin/bash
set -euo pipefail

groups=(
	"lua LUA:openresty/lua-nginx-module STREAM_LUA:openresty/stream-lua-nginx-module RESTY_CORE:openresty/lua-resty-core"
	"luajit LUAJIT:openresty/luajit2"
	"ndk NDK:openresty/ngx_devel_kit"
	"lrucache RESTY_LRUCACHE:openresty/lua-resty-lrucache"
	"resty-string RESTY_STRING:openresty/lua-resty-string"
	"cjson CJSON:openresty/lua-cjson"
)

pattern() {
	case $1 in
	LUAJIT) echo '^v2\.1-[0-9]{8}$' ;;
	CJSON) echo '^2\.1\.0\.[0-9]+$' ;;
	*) echo '^v[0-9]+(\.[0-9]+)+(rc[0-9]+)?$' ;;
	esac
}

newest() {
	local refs tag sha
	refs=$(git ls-remote --tags "https://github.com/$2")
	tag=$(printf '%s\n' "$refs" | sed -n 's|.*refs/tags/\([^^]*\)$|\1|p' | grep -E "$(pattern "$1")" | sed 's/rc/~rc/' | sort -V | tail -n 1 | sed 's/~rc/rc/')
	[ -n "$tag" ] || return 1
	sha=$(printf '%s\n' "$refs" | awk -v t="refs/tags/$tag^{}" '$2 == t {print $1}')
	[ -n "$sha" ] || sha=$(printf '%s\n' "$refs" | awk -v t="refs/tags/$tag" '$2 == t {print $1}')
	echo "$tag $sha"
}

for g in "${groups[@]}"; do
	read -r name mods <<<"$g"
	changed=false
	edits=()
	tags=()
	for m in $mods; do
		arg=${m%%:*}
		repo=${m#*:}
		cur=$(sed -n "s/^ARG $arg=//p" Dockerfile)
		read -r tag sha <<<"$(newest "$arg" "$repo")"
		tags+=("${repo#*/} $tag")
		edits+=("s/^ARG $arg=.*/ARG $arg=$sha/")
		[ "$sha" = "$cur" ] || changed=true
	done
	$changed || continue
	printf '%s\t%s\t' "$name" "$(IFS=,; echo "${tags[*]}" | sed 's/,/, /g')"
	(IFS=';'; echo "${edits[*]}")
done
