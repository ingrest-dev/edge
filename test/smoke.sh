#!/bin/sh
set -eu
image=$1
name=edge-smoke-$$
here=$(cd "$(dirname "$0")" && pwd)
docker run --rm "$image" openresty -V 2>&1 | grep -q -- "--with-http_v3_module"
n=$(docker run --rm "$image" sh -c 'grep -c "\"ctx\"" /usr/local/openresty/directives.json')
[ "$n" -gt 500 ] || { echo "directives.json has $n forms"; exit 1; }
docker run -d --name "$name" -p 127.0.0.1:18080:8080 -v "$here/nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf:ro" "$image" openresty -g "daemon off;" >/dev/null
trap 'docker rm -f "$name" >/dev/null' EXIT
i=0
until curl -fs -o /dev/null http://127.0.0.1:18080/; do
	i=$((i + 1))
	[ "$i" -lt 30 ] || { docker logs "$name"; exit 1; }
	sleep 1
done
for enc in br zstd; do
	got=$(curl -fs -o /dev/null -w '%header{content-encoding}' -H "Accept-Encoding: $enc" http://127.0.0.1:18080/)
	[ "$got" = "$enc" ] || { echo "content-encoding $enc: got '$got'"; exit 1; }
done
echo ok
