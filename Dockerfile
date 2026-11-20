FROM debian:trixie-20261104-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 AS sources

ARG VERSION
ARG LUAJIT=2769af8852a4b32687dfdfc55040c4cb4e6a8417
ARG NDK=3bd7c5619312ca562c5fd5dda238cb8d73bf2a1d
ARG LUA=0b5ce7ed53591f212c73378a027dd65e7da3a932
ARG STREAM_LUA=57ff1388e020bf918b243f2bae809fa8c84e39b8
ARG RESTY_CORE=8c8091a829fc5209980821c3845f936851d5c5e5
ARG RESTY_LRUCACHE=3ff6300e68b73ba20e909c7d16bd839aef2e5a4b
ARG RESTY_STRING=282590f58d4c927226492e0211b974d72b759329
ARG CJSON=5f53e878d0441e1555f53060178c61d161079e06
ARG BROTLI=53e0fb55f250f48fe80c0ddbf6c0f7103cdbaae1
ARG BROTLI_LIB=db24a98aed38a16de78cc05ca15cdd8dc2a0d92d
ARG ZSTD=6bce903d3f02416d478fb11efeb0303945bdbca9
ARG GEOIP2=445df24ef3781e488cee3dfe8a1e111997fc1dfe
ARG MODSECURITY=3f4b57df10ce43b1f1c722141f7621dc64838be8

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
    && fetch modsecurity owasp-modsecurity/ModSecurity-nginx "${MODSECURITY}"

COPY patches /patches
RUN for d in /patches/*/; do \
        [ -d "$d" ] || continue; \
        for p in "$d"*.patch; do [ ! -e "$p" ] || git -C "/src/$(basename "$d")" apply "$p" || exit 1; done; \
    done \
    && { printf '%s\n' "${VERSION}" "${LUAJIT}" "${NDK}" "${LUA}" "${STREAM_LUA}" "${RESTY_CORE}" "${RESTY_LRUCACHE}" "${RESTY_STRING}" "${CJSON}" \
        "${BROTLI}" "${BROTLI_LIB}" "${ZSTD}" "${GEOIP2}" "${MODSECURITY}"; find /patches -name '*.patch' -type f | sort | xargs -r sha256sum; } \
        | sha256sum | cut -c1-16 >/src/fingerprint

FROM golang:1.27.4-trixie@sha256:b54b2639de8c1bfe538ec5ffc45f29b1932235ac5f6d63c059853646677112d9 AS directives

ENV GOTOOLCHAIN=local GOTELEMETRY=off GOFLAGS=-mod=mod
COPY --from=sources /src /src
COPY tools/directives /tools/directives
RUN sh /tools/directives/generate.sh /src "$(cat /src/fingerprint /tools/directives/generate.sh /tools/directives/main.go | sha256sum | cut -c1-16)" /directives.json

FROM sources AS build

ARG VERSION
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential cmake perl pkg-config \
        libssl-dev libpcre2-dev zlib1g-dev libmaxminddb-dev libzstd-dev libmodsecurity-dev \
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
        libssl3t64 libpcre2-8-0 zlib1g libmaxminddb0 libzstd1 libmodsecurity3t64 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/nginx /usr/local/nginx
COPY --from=build /usr/local/luajit /usr/local/luajit
COPY --from=directives /directives.json /usr/local/nginx/directives.json
ENV PATH=/usr/local/nginx/sbin:$PATH
STOPSIGNAL SIGQUIT
