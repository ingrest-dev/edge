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
	-p 127.0.0.1:19001:9001 -p 127.0.0.1:19443:9443 \
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
got=$(curl -fs -D "$work/headers" http://127.0.0.1:18080/balancer)
[ "$got" = backend ] || fail "balancer_by_lua: got '$got'"
grep -qi '^x-failure: failed' "$work/headers" || fail "balancer retry or header_filter_by_lua: $(cat "$work/headers")"
got=$(curl -fs http://127.0.0.1:18080/logged)
[ "$got" = "502, 200 failed" ] || fail "log_by_lua: got '$got'"
got=$(curl -s http://127.0.0.1:18080/api)
[ "$got" = ok ] || fail "Lua API: got '$got'"
got=$(curl -fs --data-binary edge http://127.0.0.1:18080/body)
[ "$got" = "POST edge" ] || fail "request body: got '$got'"
got=$(curl -s -o /dev/null -w '%{http_code}' --data-binary edge http://127.0.0.1:18080/deny)
[ "$got" = 403 ] || fail "ngx.status 403: got '$got'"
got=$(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:18080/waf?x=bad')/$(curl -fs 'http://127.0.0.1:18080/waf?x=good')
[ "$got" = 403/pass ] || fail "modsecurity: got '$got'"
upload() {
	printf -- '--b\r\nContent-Disposition: form-data; name="f"; %s\r\n\r\nx\r\n--b--\r\n' "$1" >"$work/upload"
	curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: multipart/form-data; boundary=b' --data-binary "@$work/upload" http://127.0.0.1:18080/waf
}
got=$(upload 'filename="ok.txt"')/$(upload "filename=\"ok.txt\"; filename*=UTF-8''shell.php")
[ "$got" = 200/403 ] || fail "modsecurity multipart filename*: got '$got'"
got=$(docker exec "$name" curl -sk --http3-only -o /dev/null -w '%{http_version} %{http_code}' https://127.0.0.1:8443/)
[ "$got" = "3 200" ] || fail "HTTP/3: got '$got'"
got=$(curl -sk --http2 https://127.0.0.1:18443/hello https://127.0.0.1:18443/hello | tr '\n' ' ')
[ "$got" = "tcp ok tcp ok " ] || fail "ssl_client_hello_by_lua, clienthello API or ngx.ctx to requests: got '$got'"
got=$(docker exec "$name" curl -sk --http3-only https://127.0.0.1:8443/hello https://127.0.0.1:8443/hello | tr '\n' ' ')
[ "$got" = "quic ok quic ok " ] || fail "ssl_client_hello_by_lua over QUIC: got '$got'"
got=$(curl -fs http://127.0.0.1:19000/)
[ "$got" = backend ] || fail "stream balancer_by_lua: got '$got'"
for c in fallback lua; do
	got=$(echo | openssl s_client -connect 127.0.0.1:18443 -servername "$c.test" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null)
	case "$got" in *"$c.test"*) ;; *) fail "certificate for $c.test: got '$got'" ;; esac
done
got=$(echo | openssl s_client -connect 127.0.0.1:19443 -servername lua.test 2>/dev/null | openssl x509 -noout -subject 2>/dev/null)
case "$got" in *lua.test*) ;; *) fail "stream ssl_preread passthrough: got '$got'" ;; esac
i=0
until got=$(curl -s --http0.9 http://127.0.0.1:19001/) && [ "${got##*, }" != nothing ]; do
	i=$((i + 1))
	[ "$i" -lt 20 ] || break
	sleep 0.2
done
[ "$got" = "8081 stream true, lua.test" ] || fail "stream preread, balancer ctx or log_by_lua: got '$got'"
if docker logs "$name" 2>&1 | grep -E '\[(alert|crit|emerg)\]'; then
	fail "alerts in the error log"
fi
echo ok
