#!/bin/sh
set -eu
src=$1
source=$2
out=$3
crossplane=github.com/nginxinc/nginx-go-crossplane/cmd/generate@v0.4.89
here=$(cd "$(dirname "$0")" && pwd)
tree=$(mktemp -d)
cp -r "$src"/openresty-* "$tree/"
or=$(ls -d "$tree"/openresty-*)
rm -rf "$or"/bundle/ngx_postgres-* "$or"/bundle/drizzle-nginx-module-* "$or"/bundle/iconv-nginx-module-* \
    "$or"/bundle/nginx-*/src/mail "$or"/bundle/nginx-*/src/http/modules/perl
for m in image_filter xslt_filter geoip degradation; do
    rm -f "$or"/bundle/nginx-*/src/http/modules/ngx_http_${m}_module.c
done
rm -f "$or"/bundle/nginx-*/src/stream/ngx_stream_geoip_module.c "$or"/bundle/nginx-*/src/misc/ngx_google_perftools_module.c
for m in brotli zstd geoip2 modsecurity; do
    cp -r "$src/$m" "$tree/$m"
done
rm -rf "$tree"/brotli/deps "$tree"/*/.git
go run "$crossplane" --src-path "$tree" --directive-map-name edgeDirectives --match-func-name MatchEdge >"$tree.gen.go"
cd "$here"
go run . "$tree.gen.go" "$source" "$out"
rm -rf "$tree" "$tree.gen.go"
