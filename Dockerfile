FROM debian:trixie-20261104-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 AS sources

ARG VERSION
ARG LUAJIT=2769af8852a4b32687dfdfc55040c4cb4e6a8417
ARG NDK=3bd7c5619312ca562c5fd5dda238cb8d73bf2a1d
ARG LUA=43c620962d8d23e534208165ab3f1c68c8fe887b
ARG STREAM_LUA=6cc2b8d3de895dacae406e6873cd5b4833190f5d
ARG RESTY_CORE=8c8091a829fc5209980821c3845f936851d5c5e5
ARG RESTY_LRUCACHE=20869bd34742fa20344c29fe31d4d6506d6827bf
ARG RESTY_STRING=be19d0f70548a2deb73f5b426af51541be0d7ef9
ARG CJSON=5f53e878d0441e1555f53060178c61d161079e06
ARG BROTLI=53e0fb55f250f48fe80c0ddbf6c0f7103cdbaae1
ARG BROTLI_LIB=db24a98aed38a16de78cc05ca15cdd8dc2a0d92d
ARG ZSTD=4a0019c89b18ed7a6d27967aab9c3a26f566788b
ARG GEOIP2=445df24ef3781e488cee3dfe8a1e111997fc1dfe
ARG MODSECURITY=8de0e0ec5b786d9a6f2d23133f63eced730b2f7d
ARG LIBMODSECURITY=1925753989ccce977cdaae417b55c9726c7cf02c

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git gpgv \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY keys/nginx.gpg /keys/nginx.gpg
RUN test -n "${VERSION}" \
    && nginx="${VERSION%.*}" \
    && curl -fsSL --retry 5 -o /tmp/nginx.tar.gz "https://nginx.org/download/nginx-${nginx}.tar.gz" \
    && curl -fsSL --retry 5 -o /tmp/nginx.tar.gz.asc "https://nginx.org/download/nginx-${nginx}.tar.gz.asc" \
    && gpgv --keyring /keys/nginx.gpg /tmp/nginx.tar.gz.asc /tmp/nginx.tar.gz \
    && mkdir nginx && tar xzf /tmp/nginx.tar.gz -C nginx --strip-components 1 \
    && rm /tmp/nginx.tar.gz*

RUN fetch() { git init -q "$1" && git -C "$1" fetch -q --depth 1 "https://github.com/$2" "$3" && git -C "$1" checkout -q FETCH_HEAD && test "$(git -C "$1" rev-parse HEAD)" = "$3"; } \
    && fetch luajit openresty/luajit2 "${LUAJIT}" \
    && fetch ndk openresty/ngx_devel_kit "${NDK}" \
    && fetch lua openresty/lua-nginx-module "${LUA}" \
    && fetch stream-lua openresty/stream-lua-nginx-module "${STREAM_LUA}" \
    && fetch resty-core openresty/lua-resty-core "${RESTY_CORE}" \
    && fetch resty-lrucache openresty/lua-resty-lrucache "${RESTY_LRUCACHE}" \
    && fetch resty-string openresty/lua-resty-string "${RESTY_STRING}" \
    && fetch cjson openresty/lua-cjson "${CJSON}" \
    && fetch brotli google/ngx_brotli "${BROTLI}" \
    && rm -rf brotli/deps/brotli && fetch brotli/deps/brotli google/brotli "${BROTLI_LIB}" \
    && fetch zstd GetPageSpeed/zstd-nginx-module "${ZSTD}" \
    && fetch geoip2 leev/ngx_http_geoip2_module "${GEOIP2}" \
    && fetch modsecurity owasp-modsecurity/ModSecurity-nginx "${MODSECURITY}" \
    && fetch libmodsecurity owasp-modsecurity/ModSecurity "${LIBMODSECURITY}" \
    && git -C libmodsecurity submodule update -q --init --recursive --depth 1 others/libinjection others/mbedtls

COPY patches /patches
RUN for d in /patches/*/; do \
        [ -d "$d" ] || continue; \
        for p in "$d"*.patch; do [ ! -e "$p" ] || git -C "/src/$(basename "$d")" apply "$p" || exit 1; done; \
    done \
    && { printf '%s\n' "${VERSION}" "${LUAJIT}" "${NDK}" "${LUA}" "${STREAM_LUA}" "${RESTY_CORE}" "${RESTY_LRUCACHE}" "${RESTY_STRING}" "${CJSON}" \
        "${BROTLI}" "${BROTLI_LIB}" "${ZSTD}" "${GEOIP2}" "${MODSECURITY}" "${LIBMODSECURITY}"; find /patches -name '*.patch' -type f | sort | xargs -r sha256sum; } \
        | sha256sum | cut -c1-16 >/src/fingerprint

FROM golang:1.27.4-trixie@sha256:f18c3d73a184fb0582828510722e723b63a93f7188d11dd223d9be6f6880e65d AS directives

ENV GOTOOLCHAIN=local GOTELEMETRY=off GOFLAGS=-mod=mod
COPY --from=sources /src /src
COPY tools/directives /tools/directives
RUN sh /tools/directives/generate.sh /src "$(cat /src/fingerprint /tools/directives/generate.sh /tools/directives/main.go | sha256sum | cut -c1-16)" /directives.json

FROM sources AS build

ARG VERSION
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential cmake perl pkg-config autoconf automake libtool \
        libssl-dev libpcre2-dev zlib1g-dev libmaxminddb-dev libzstd-dev libyajl-dev \
    && rm -rf /var/lib/apt/lists/*

COPY build.sh /build.sh
RUN sh /build.sh "${VERSION}"

FROM debian:trixie-20261104-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

ARG VERSION
LABEL dev.ingrest.image=edge \
      org.opencontainers.image.source=https://github.com/ingrest-dev/edge \
      org.opencontainers.image.description="nginx with Lua for the Ingrest panel" \
      org.opencontainers.image.licenses=AGPL-3.0-only \
      org.opencontainers.image.version="${VERSION}"

RUN --mount=type=bind,source=REFRESH,target=/tmp/refresh apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && apt-get install -y --no-install-recommends ca-certificates curl \
        libssl3t64 libpcre2-8-0 zlib1g libmaxminddb0 libzstd1 libyajl2 libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/nginx /usr/local/nginx
COPY --from=build /usr/local/luajit /usr/local/luajit
COPY --from=build /usr/local/modsecurity/lib /usr/local/modsecurity/lib
COPY --from=directives /directives.json /usr/local/nginx/directives.json
ENV PATH=/usr/local/nginx/sbin:$PATH
STOPSIGNAL SIGQUIT
