#!/bin/bash
set -euo pipefail

groups=(
	"lua LUA:openresty/lua-nginx-module STREAM_LUA:openresty/stream-lua-nginx-module RESTY_CORE:openresty/lua-resty-core"
	"luajit LUAJIT:openresty/luajit2"
	"ndk NDK:openresty/ngx_devel_kit"
	"lrucache RESTY_LRUCACHE:openresty/lua-resty-lrucache"
	"resty-string RESTY_STRING:openresty/lua-resty-string"
	"cjson CJSON:openresty/lua-cjson"
	"ngx-brotli BROTLI:google/ngx_brotli"
	"brotli BROTLI_LIB:google/brotli"
	"zstd ZSTD:GetPageSpeed/zstd-nginx-module"
	"geoip2 GEOIP2:leev/ngx_http_geoip2_module"
	"modsecurity MODSECURITY:owasp-modsecurity/ModSecurity-nginx"
	"libmodsecurity LIBMODSECURITY:owasp-modsecurity/ModSecurity"
)

security='CVE-[0-9]{4}-[0-9]+|GHSA-|\bsecurity\b|vulnerab|overflow|out[- ]of[- ]bounds|use[- ]after[- ]free|double[- ]free|\bfreed\b|segfault|crash|null pointer|\bNULL\b|heap|memory (leak|corruption)|\bleak|uninitiali|bypass|enforce|smuggl|denial of service|\bDoS\b|infinite loop|\brace\b'

pattern() {
	case $1 in
	BROTLI | GEOIP2) echo HEAD ;;
	LUAJIT) echo '^v2\.1-[0-9]{8}$' ;;
	CJSON) echo '^2\.1\.0\.[0-9]+$' ;;
	BROTLI_LIB | MODSECURITY) echo '^v[0-9]+\.[0-9]+\.[0-9]+$' ;;
	LIBMODSECURITY) echo '^v3\.[0-9]+\.[0-9]+$' ;;
	ZSTD) echo '^[0-9]+\.[0-9]+\.[0-9]+$' ;;
	*) echo '^v[0-9]+(\.[0-9]+)+(rc[0-9]+)?$' ;;
	esac
}

newest() {
	local refs tag sha p
	p=$(pattern "$1")
	if [ "$p" = HEAD ]; then
		sha=$(git ls-remote "https://github.com/$2" HEAD | awk '{print $1}') || return 1
		echo "HEAD $sha"
		return
	fi
	refs=$(git ls-remote --tags "https://github.com/$2") || return 1
	tag=$(printf '%s\n' "$refs" | sed -n 's|.*refs/tags/\([^^]*\)$|\1|p' | grep -E "$p" | sed 's/rc/~rc/' | sort -V | tail -n 1 | sed 's/~rc/rc/')
	[ -n "$tag" ] || return 1
	sha=$(printf '%s\n' "$refs" | awk -v t="refs/tags/$tag^{}" '$2 == t {print $1}')
	[ -n "$sha" ] || sha=$(printf '%s\n' "$refs" | awk -v t="refs/tags/$tag" '$2 == t {print $1}')
	echo "$tag $sha"
}

subjects() {
	gh api --paginate "repos/$1/compare/$2...$3?per_page=100" --jq '.commits[].commit.message | gsub("\n"; " ")' 2>/dev/null
}

fixes() {
	gh api --paginate "repos/$1/compare/$2...$3?per_page=100" --jq '.commits[].commit.message | split("\n")[0]' 2>/dev/null \
		| grep -viE '^(docs|ci|test|tests|chore|style)(\(|:)|^Merge ' | grep -ciE "$security"
}

status_of() {
	gh api "repos/$1/compare/$2...$3" --jq .status 2>/dev/null || echo unknown
}

untagged() {
	local repo=$1 cur=$2 tag=$3 head base hits
	head=$(git ls-remote "https://github.com/$repo" HEAD | awk '{print $1}') || return 1
	[[ "$head" =~ ^[0-9a-f]{40}$ ]] && [ "$head" != "$tag" ] && [ "$head" != "$cur" ] || return 1
	base=$tag
	[ "$(status_of "$repo" "$tag" "$cur")" != ahead ] || base=$cur
	[ "$(status_of "$repo" "$base" "$head")" = ahead ] || return 1
	hits=$(fixes "$repo" "$base" "$head") || return 1
	echo "$head $hits"
}

advisories() {
	local since
	since=$(gh api "repos/$1/commits/$2" --jq .commit.committer.date 2>/dev/null) || return 0
	gh api "repos/$1/security-advisories?state=published&per_page=100" \
		--jq ".[] | select(.published_at > \"$since\") | \"\(.ghsa_id) \(.cve_id // \"\") \(.severity): \(.summary)\"" 2>/dev/null || true
}

bodies=${BODIES:-$(mktemp -d)}
mkdir -p "$bodies"
for g in "${groups[@]}"; do
	read -r name mods <<<"$g"
	changed=false
	edits=()
	tags=()
	body=$bodies/$name.md
	: >"$body"
	for m in $mods; do
		arg=${m%%:*}
		repo=${m#*:}
		cur=$(sed -n "s/^ARG $arg=//p" Dockerfile)
		out=$(newest "$arg" "$repo") || { echo "no release ref for $repo" >&2; exit 1; }
		read -r tag sha <<<"$out"
		[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "bad sha '$sha' for $repo $tag" >&2; exit 1; }
		[ "$tag" != HEAD ] || tag=${sha:0:12}
		untagged=
		if [ "$tag" != "${sha:0:12}" ] && fixes=$(untagged "$repo" "$cur" "$sha"); then
			read -r head hits <<<"$fixes"
			tag="${head:0:12} (default branch: untagged fixes)"
			sha=$head
			untagged=$hits
		fi
		if [ "$sha" = "$cur" ]; then
			tags+=("${repo#*/} $tag")
			continue
		fi
		if ! status=$(gh api "repos/$repo/compare/$cur...$sha" --jq .status 2>"$bodies/err"); then
			status=unknown
			! grep -qE 'HTTP (404|422)' "$bodies/err" || status=unrelated
		fi
		if [ "$status" = behind ] || [ "$status" = unknown ]; then
			echo "$repo $tag is $status against the pinned $cur: kept" >&2
			tags+=("${repo#*/} ${cur:0:12}")
			continue
		fi
		tags+=("${repo#*/} $tag")
		edits+=("s/^ARG $arg=.*/ARG $arg=$sha/")
		changed=true
		echo "- [$repo $tag](https://github.com/$repo/compare/$cur...$sha) ($status)" >>"$body"
		[ -z "$untagged" ] || echo "  - no release has these fixes yet: $untagged fix subjects matched security words" >>"$body"
		adv=$(advisories "$repo" "$cur")
		[ -z "$adv" ] || printf '%s\n' "$adv" | tr -d '`' | sed 's/^/  - security? advisory `/; s/$/`/' >>"$body"
		if msgs=$(subjects "$repo" "$cur" "$sha"); then
			hits=$(printf '%s\n' "$msgs" | grep -iE "$security" | cut -c1-200 | tr -d '`' || true)
			[ -z "$hits" ] || printf '%s\n' "$hits" | sed 's/^/  - security? `/; s/$/`/' >>"$body"
		else
			echo "  - commits not compared" >>"$body"
		fi
	done
	$changed || continue
	sec=false
	! grep -q 'security? ' "$body" || sec=true
	printf '%s\t%s\t%s\t' "$name" "$(IFS=,; echo "${tags[*]}" | sed 's/,/, /g')" "$sec"
	(IFS=';'; echo "${edits[*]}")
done
