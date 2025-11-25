ARG NGINX_VER=1.29.3
ARG LUAROCKS_VER=3.12.2
ARG DEBIAN_VER=bookworm-slim

# ============================
# Builder stage
# ============================
FROM debian:${DEBIAN_VER} AS builder
ARG NGINX_VER
ARG LUAROCKS_VER
ENV LUAJIT_LIB=/usr/local/lib
ENV LUAJIT_INC=/usr/local/include/luajit-2.1

# 安装编译依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl wget cmake unzip \
    libpcre3-dev zlib1g-dev libssl-dev \
    libmaxminddb-dev libreadline-dev perl pkg-config ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# ---- LuaJIT ----
RUN git clone https://github.com/openresty/luajit2.git /luajit2 && \
    cd /luajit2 && make -j$(nproc) && make install

# ---- LuaRocks ----
RUN mkdir /luarocks && \
    curl -L https://luarocks.org/releases/luarocks-${LUAROCKS_VER}.tar.gz -o /tmp/luarocks.tar.gz && \
    tar xzf /tmp/luarocks.tar.gz -C /luarocks --strip-components=1 && \
    cd /luarocks && ./configure \
        --with-lua=/usr/local \
        --with-lua-include=/usr/local/include/luajit-2.1 \
        --with-lua-lib=/usr/local/lib && \
    make -j$(nproc) && make install

# ---- Nginx + Modules ----
RUN mkdir /nginx && \
    curl -L https://nginx.org/download/nginx-${NGINX_VER}.tar.gz -o /tmp/nginx.tar.gz && \
    tar xzf /tmp/nginx.tar.gz -C /nginx --strip-components=1 && \
    rm /tmp/nginx.tar.gz && \
    \
    git clone https://github.com/leev/ngx_http_geoip2_module.git /modules/geoip2 && \
    git clone https://github.com/openresty/lua-nginx-module.git /modules/lua && \
    git clone https://github.com/openresty/stream-lua-nginx-module.git /modules/stream-lua && \
    git clone https://github.com/openresty/lua-resty-core.git /libs/core && \
    git clone https://github.com/openresty/lua-resty-lrucache.git /libs/lrucache && \
    \
    cd /nginx && \
    ./configure \
        --prefix=/etc/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --with-compat \
        --with-stream \
        --with-http_ssl_module \
        --with-http_auth_request_module \
        --add-dynamic-module=/modules/geoip2 \
        --add-dynamic-module=/modules/lua \
        --add-dynamic-module=/modules/stream-lua \
        --with-cc-opt="-I/usr/local/include/luajit-2.1" \
        --with-ld-opt="-L/usr/local/lib" && \
    make -j$(nproc) && \
    make -j$(nproc) modules

# ============================
# Final runtime image
# ============================
FROM debian:${DEBIAN_VER}

# 安装 runtime 依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpcre3 \
    libmaxminddb0 \
    curl \
    bash \
    tzdata \
    python3-certbot \
    python3-certbot-nginx \
    logrotate \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# 设置东京时区
RUN ln -snf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && echo "Asia/Tokyo" > /etc/timezone

# logrotate nginx 配置
RUN mkdir -p /etc/logrotate.d && \
    printf "/var/log/nginx/*.log {\n\
    daily\n\
    missingok\n\
    rotate 7\n\
    compress\n\
    delaycompress\n\
    notifempty\n\
    sharedscripts\n\
    postrotate\n\
        [ -s /run/nginx.pid ] && kill -USR1 $(cat /run/nginx.pid)\n\
    endscript\n\
}\n" > /etc/logrotate.d/nginx

RUN groupadd -r nginx && useradd -r -g nginx -s /sbin/nologin -M nginx

# 复制编译好的 Nginx 和相关文件
COPY --from=builder /nginx/objs/nginx /usr/sbin/nginx
COPY --from=builder /nginx/conf /etc/nginx
RUN rm -rf /etc/nginx/sites-available \
           /etc/nginx/sites-enabled \
           /etc/nginx/snippets \
           /etc/nginx/modules-enabled \
           /etc/nginx/modules-available
COPY --from=builder /nginx/html /usr/share/nginx/html

# 创建 Nginx 运行时目录
RUN mkdir -p /var/log/nginx /var/cache/nginx /run/nginx && \
    chown -R nginx:nginx /var/log/nginx /var/cache/nginx /run/nginx

# 复制动态模块
COPY --from=builder /usr/local/lib/libluajit* /usr/local/lib/
RUN ldconfig
COPY --from=builder /nginx/objs/*.so /etc/nginx/modules/
COPY --from=builder /libs/core/lib/resty /usr/local/lib/lua/5.1/resty
COPY --from=builder /libs/lrucache/lib/resty /usr/local/lib/lua/5.1/resty
COPY --from=builder /usr/local/bin/luarocks /usr/local/bin/
COPY --from=builder /usr/local/share/lua/5.1/luarocks /usr/local/share/lua/5.1/luarocks

# 复制自定义 nginx 配置文件
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80 443
WORKDIR /etc/nginx
CMD ["nginx", "-g", "daemon off;"]
