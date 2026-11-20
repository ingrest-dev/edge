#!/bin/sh
set -eu
src=$1
source=$2
out=$3
crossplane=github.com/nginxinc/nginx-go-crossplane/cmd/generate@v0.4.89
here=$(cd "$(dirname "$0")" && pwd)
tree=$(mktemp -d)
for m in nginx ndk lua stream-lua brotli zstd geoip2 modsecurity; do
    cp -r "$src/$m" "$tree/$m"
done
rm -rf "$tree"/nginx/src/mail "$tree"/nginx/src/http/modules/perl "$tree"/brotli/deps "$tree"/*/.git
for m in image_filter xslt_filter geoip degradation; do
    rm -f "$tree"/nginx/src/http/modules/ngx_http_${m}_module.c
done
rm -f "$tree"/nginx/src/stream/ngx_stream_geoip_module.c "$tree"/nginx/src/misc/ngx_google_perftools_module.c \
    "$tree"/geoip2/ngx_stream_geoip2_module.c
go run "$crossplane" --src-path "$tree" --directive-map-name edgeDirectives --match-func-name MatchEdge >"$tree.gen.go"
cd "$here"
go run . "$tree.gen.go" "$source" "$out"
rm -rf "$tree" "$tree.gen.go"
