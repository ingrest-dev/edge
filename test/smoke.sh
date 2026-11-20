#!/bin/sh
set -eu
image=$1
name=edge-smoke-$$
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT
fail() { echo "$*"; docker logs "$name" 2>&1 | tail -20 || true; exit 1; }

build="ingrest-$(sed 's/.*\.//' "$here/../VERSION")"
docker run --rm "$image" nginx -V 2>&1 | grep -q -- "--with-http_v3_module" || fail "nginx -V lacks http_v3"
docker run --rm "$image" nginx -v 2>&1 | grep -qF "($build)" || fail "nginx -v lacks $build"
n=$(docker run --rm "$image" sh -c 'grep -c "\"ctx\"" /usr/local/nginx/directives.json')
[ "$n" -gt 500 ] || fail "directives.json has $n forms"
docker run --rm "$image" sh -c '! ls /usr/local/nginx/modules/ngx_stream_geoip2_module.so 2>/dev/null' || fail "stream geoip2 module is shipped"

for c in fallback lua; do
	openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj "/CN=$c.test" \
		-keyout "$work/$c.key" -out "$work/$c.crt" 2>/dev/null
done
cp "$here/nginx.conf" "$work/nginx.conf"
chmod 644 "$work"/*
docker run -d --name "$name" --read-only --tmpfs /tmp -p 127.0.0.1:18080:8080 -p 127.0.0.1:18443:8443 -p 127.0.0.1:19000:9000 \
	-v "$work:/test:ro" "$image" nginx -e stderr -c /test/nginx.conf -g "daemon off;" >/dev/null
i=0
until curl -fs -o /dev/null http://127.0.0.1:18080/; do
	i=$((i + 1))
	[ "$i" -lt 30 ] || fail "edge did not start"
	sleep 1
done

for enc in br zstd; do
	got=$(curl -fs -o /dev/null -w '%header{content-encoding}' -H "Accept-Encoding: $enc" http://127.0.0.1:18080/)
	[ "$got" = "$enc" ] || fail "content-encoding $enc: got '$got'"
done
got=$(curl -fs http://127.0.0.1:18080/libs)
[ "$got" = 'ndk v {"ok":true} a1cb100f' ] || fail "libs: got '$got'"
got=$(curl -fs http://127.0.0.1:18080/balancer)
[ "$got" = backend ] || fail "balancer_by_lua: got '$got'"
got=$(curl -fs http://127.0.0.1:19000/)
[ "$got" = backend ] || fail "stream balancer_by_lua: got '$got'"
for c in fallback lua; do
	got=$(echo | openssl s_client -connect 127.0.0.1:18443 -servername "$c.test" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null)
	case "$got" in *"$c.test"*) ;; *) fail "certificate for $c.test: got '$got'" ;; esac
done
if docker logs "$name" 2>&1 | grep -E '\[(alert|crit|emerg)\]'; then
	fail "alerts in the error log"
fi
echo ok
