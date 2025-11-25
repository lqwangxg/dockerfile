ARG NGINX_VER=1.29.3
ARG LUAROCKS_VER=3.12.2

# ============================
# Builder stage (optimized)
# ============================
FROM alpine AS builder-base
RUN apk add --no-cache build-base git curl perl cmake

# ---- Download LuaJIT (cacheable) ----
FROM builder-base AS luajit-src
RUN mkdir /src && \
    git clone https://github.com/openresty/luajit2.git /src

# ---- Download LuaRocks (cacheable) ----
FROM builder-base AS luarocks-src
ARG LUAROCKS_VER
RUN mkdir /src && \
    curl -L https://luarocks.org/releases/luarocks-${LUAROCKS_VER}.tar.gz -o luarocks.tar.gz && \
    tar xzf luarocks.tar.gz -C /src --strip-components=1

# ---- Download Nginx + Modules (cacheable) ----
FROM builder-base AS nginx-src
ARG NGINX_VER
RUN mkdir /src && \
    curl -L https://nginx.org/download/nginx-${NGINX_VER}.tar.gz -o nginx.tar.gz && \
    tar xzf nginx.tar.gz -C /src --strip-components=1
RUN git clone https://github.com/leev/ngx_http_geoip2_module.git /modules/geoip2 && \
    git clone https://github.com/openresty/lua-nginx-module.git /modules/lua && \
    git clone https://github.com/openresty/stream-lua-nginx-module.git /modules/stream-lua && \
    git clone https://github.com/openresty/lua-resty-core.git /libs/core && \
    git clone https://github.com/openresty/lua-resty-lrucache.git /libs/lrucache

# ============================
# Build stage
# ============================
FROM alpine AS builder
ARG NGINX_VER
ENV LUAJIT_LIB=/usr/local/lib
ENV LUAJIT_INC=/usr/local/include/luajit-2.1

RUN apk add --no-cache \
    build-base pcre-dev openssl-dev zlib-dev linux-headers \
    libmaxminddb-dev readline-dev geoip-dev

COPY --from=luajit-src /src /luajit2
RUN cd /luajit2 && make -j$(nproc) && make install

COPY --from=luarocks-src /src /luarocks
RUN cd /luarocks && ./configure \
    --with-lua=/usr/local \
    --with-lua-include=/usr/local/include/luajit-2.1 \
    --with-lua-lib=/usr/local/lib && \
    make -j$(nproc) && make install

COPY --from=nginx-src /src /nginx
COPY --from=nginx-src /modules /modules
COPY --from=nginx-src /libs /libs

RUN cd /nginx && \
    ./configure \
    --with-compat \
    --with-stream \
    --add-dynamic-module=/modules/geoip2 \
    --add-dynamic-module=/modules/lua \
    --add-dynamic-module=/modules/stream-lua \
    --with-cc-opt="-I/usr/local/include/luajit-2.1" \
    --with-ld-opt="-L/usr/local/lib" && \
    make -j$(nproc) modules

# ============================
# Final tiny runtime image
# ============================
FROM nginx:${NGINX_VER}-alpine
RUN apk add --no-cache libmaxminddb luajit

COPY --from=builder /usr/local/lib/libluajit* /usr/local/lib/
COPY --from=builder /nginx/objs/*.so /etc/nginx/modules/
COPY --from=builder /libs/core/lib/resty /usr/local/lib/lua/resty
COPY --from=builder /libs/lrucache/lib/resty /usr/local/lib/lua/resty
COPY --from=builder /usr/local/bin/luarocks /usr/local/bin/
COPY --from=builder /usr/local/share/lua/5.1/luarocks /usr/local/share/lua/5.1/luarocks

EXPOSE 80 443
CMD ["nginx", "-g", "daemon off;"]


# 必须安装 certbot / bash / logrotate / timezone
RUN apk update && apk add --no-cache \
        bash \
        tzdata \
        certbot certbot-nginx \
        logrotate && \
    cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    echo "Asia/Tokyo" > /etc/timezone
#
## logrotate nginx 配置
#RUN mkdir -p /etc/logrotate.d && \
#    printf "/var/log/nginx/*.log {\n\
#    daily\n\
#    missingok\n\
#    rotate 7\n\
#    compress\n\
#    delaycompress\n\
#    notifempty\n\
#    sharedscripts\n\
#    postrotate\n\
#        [ -s /run/nginx.pid ] && kill -USR1 $(cat /run/nginx.pid)\n\
#    endscript\n\
#}\n" > /etc/logrotate.d/nginx