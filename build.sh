#!/bin/sh
set -eu
version=$1
P=/usr/local/nginx
LJ=/usr/local/luajit
LIB=$P/lualib
cd /src

cmake -S brotli/deps/brotli -B brotli/deps/brotli/out -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBROTLI_DISABLE_TESTS=ON >/dev/null
cmake --build brotli/deps/brotli/out --target brotlienc -j"$(nproc)" >/dev/null

make -C luajit -j"$(nproc)" PREFIX=$LJ >/dev/null
make -C luajit install PREFIX=$LJ >/dev/null
export LUAJIT_LIB=$LJ/lib LUAJIT_INC=$LJ/include/luajit-2.1

for m in lua:ngx_http_lua_autoconf.h stream-lua:ngx_stream_lua_autoconf.h; do
	cat >>"/src/${m%%:*}/config" <<EOF

echo '
#ifndef LUA_DEFAULT_PATH
#define LUA_DEFAULT_PATH "$LIB/?.ljbc;$LIB/?/init.ljbc;$LIB/?.lua;$LIB/?/init.lua"
#endif
#ifndef LUA_DEFAULT_CPATH
#define LUA_DEFAULT_CPATH "$LIB/?.so"
#endif
' >> "\$ngx_addon_dir/src/${m#*:}"
EOF
done

cd nginx
./configure --prefix=$P --build="ingrest-${version##*.}" \
	--with-cc-opt="-O2 -DNGX_LUA_ABORT_AT_PANIC" --with-ld-opt="-Wl,-rpath,$LJ/lib" \
	--error-log-path=stderr --http-log-path=/tmp/access.log --pid-path=/tmp/nginx.pid --lock-path=/tmp/nginx.lock \
	--http-client-body-temp-path=/tmp/client_body --http-proxy-temp-path=/tmp/proxy \
	--http-fastcgi-temp-path=/tmp/fastcgi --http-uwsgi-temp-path=/tmp/uwsgi --http-scgi-temp-path=/tmp/scgi \
	--with-compat --with-threads --with-file-aio --with-pcre-jit \
	--with-http_ssl_module --with-http_v2_module --with-http_v3_module \
	--with-http_realip_module --with-http_stub_status_module --with-http_auth_request_module \
	--with-http_gunzip_module --with-http_gzip_static_module --with-http_sub_module --with-http_secure_link_module \
	--with-http_slice_module --with-http_mp4_module --with-http_flv_module \
	--with-http_addition_module --with-http_random_index_module --with-http_dav_module \
	--with-stream --with-stream_ssl_module --with-stream_ssl_preread_module --with-stream_realip_module \
	--add-module=/src/ndk --add-module=/src/lua --add-module=/src/stream-lua \
	--add-dynamic-module=/src/brotli --add-dynamic-module=/src/zstd \
	--add-dynamic-module=/src/geoip2 --add-dynamic-module=/src/modsecurity
make -j"$(nproc)"
make install
cd /src

rm -rf $P/html $P/logs $P/modules/ngx_stream_geoip2_module.so
for lib in resty-core resty-lrucache resty-string; do
	make -C "$lib" install PREFIX=$P LUA_LIB_DIR=$LIB >/dev/null
done
make -C cjson LUA_INCLUDE_DIR="$LUAJIT_INC" >/dev/null
install -m755 cjson/cjson.so $LIB/cjson.so

for d in nginx luajit ndk lua stream-lua resty-core resty-lrucache resty-string cjson brotli zstd geoip2 modsecurity; do
	mkdir -p "$P/licenses/$d"
	for f in /src/$d/LICENSE* /src/$d/COPYRIGHT* /src/$d/COPYING* /src/$d/README.markdown /src/$d/README.md; do
		[ ! -f "$f" ] || cp "$f" "$P/licenses/$d/"
	done
done
cp brotli/deps/brotli/LICENSE "$P/licenses/brotli/LICENSE.brotli"
rm -rf $LJ/share/man
