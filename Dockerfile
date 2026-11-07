FROM debian:trixie-20261027-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS sources

ARG OPENRESTY
ARG BROTLI=53e0fb55f250f48fe80c0ddbf6c0f7103cdbaae1
ARG BROTLI_LIB=db24a98aed38a16de78cc05ca15cdd8dc2a0d92d
ARG ZSTD=6be764e2bed04f889af824eff2d4dd737ebdab5a
ARG GEOIP2=cbaa35461c62a99d2577e6bae3273492502d8769
ARG MODSECURITY=3f4b57df10ce43b1f1c722141f7621dc64838be8

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git gpgv \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY keys/openresty.gpg /keys/openresty.gpg
RUN test -n "${OPENRESTY}" \
    && curl -fsSL --retry 5 -o /tmp/openresty.tar.gz "https://openresty.org/download/openresty-${OPENRESTY}.tar.gz" \
    && curl -fsSL --retry 5 -o /tmp/openresty.tar.gz.asc "https://openresty.org/download/openresty-${OPENRESTY}.tar.gz.asc" \
    && gpgv --keyring /keys/openresty.gpg /tmp/openresty.tar.gz.asc /tmp/openresty.tar.gz \
    && tar xzf /tmp/openresty.tar.gz \
    && rm /tmp/openresty.tar.gz*

RUN fetch() { git init -q "$1" && git -C "$1" fetch -q --depth 1 "https://github.com/$2" "$3" && git -C "$1" checkout -q FETCH_HEAD && test "$(git -C "$1" rev-parse HEAD)" = "$3"; } \
    && fetch brotli google/ngx_brotli "${BROTLI}" \
    && rm -rf brotli/deps/brotli && fetch brotli/deps/brotli google/brotli "${BROTLI_LIB}" \
    && fetch zstd tokers/zstd-nginx-module "${ZSTD}" \
    && fetch geoip2 leev/ngx_http_geoip2_module "${GEOIP2}" \
    && fetch modsecurity owasp-modsecurity/ModSecurity-nginx "${MODSECURITY}" \
    && printf '%s\n' "${OPENRESTY}" "${BROTLI}" "${BROTLI_LIB}" "${ZSTD}" "${GEOIP2}" "${MODSECURITY}" | sha256sum | cut -c1-16 >/src/fingerprint

FROM golang:1.27.3-trixie@sha256:af1bfc2614ebb1dbd31af514b78740fd678850e76498762b425ecee4c5c6ea80 AS directives

ENV GOTOOLCHAIN=local GOTELEMETRY=off GOFLAGS=-mod=mod
COPY --from=sources /src /src
COPY tools/directives /tools/directives
RUN sh /tools/directives/generate.sh /src "$(cat /src/fingerprint)" /directives.json

FROM sources AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential cmake perl pkg-config \
        libssl-dev libpcre2-dev zlib1g-dev libmaxminddb-dev libzstd-dev libmodsecurity-dev \
    && rm -rf /var/lib/apt/lists/*

RUN cmake -S brotli/deps/brotli -B brotli/deps/brotli/out -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBROTLI_DISABLE_TESTS=ON >/dev/null \
    && cmake --build brotli/deps/brotli/out --target brotlienc -j"$(nproc)" >/dev/null

RUN cd "openresty-${OPENRESTY}" \
    && ./configure --prefix=/usr/local/openresty \
        --with-compat --with-threads --with-file-aio --with-pcre-jit \
        --with-http_ssl_module --with-http_v2_module --with-http_v3_module \
        --with-http_realip_module --with-http_stub_status_module --with-http_auth_request_module \
        --with-http_gunzip_module --with-http_gzip_static_module --with-http_sub_module --with-http_secure_link_module \
        --with-http_slice_module --with-http_mp4_module --with-http_flv_module \
        --with-http_addition_module --with-http_random_index_module --with-http_dav_module \
        --with-stream --with-stream_ssl_module --with-stream_ssl_preread_module --with-stream_realip_module \
        --add-dynamic-module=/src/brotli --add-dynamic-module=/src/zstd \
        --add-dynamic-module=/src/geoip2 --add-dynamic-module=/src/modsecurity \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /usr/local/openresty/nginx/html /usr/local/openresty/pod

FROM debian:trixie-20261027-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4

ARG OPENRESTY
LABEL dev.ingrest.image=edge \
      org.opencontainers.image.source=https://github.com/ingrest-dev/edge \
      org.opencontainers.image.description="OpenResty for the Ingrest panel" \
      org.opencontainers.image.licenses=AGPL-3.0-only \
      org.opencontainers.image.version="${OPENRESTY}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
        libssl3t64 libpcre2-8-0 zlib1g libmaxminddb0 libzstd1 libmodsecurity3t64 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/openresty /usr/local/openresty
COPY --from=directives /directives.json /usr/local/openresty/directives.json
ENV PATH=/usr/local/openresty/bin:/usr/local/openresty/nginx/sbin:$PATH
STOPSIGNAL SIGQUIT
