# Nginx with LuaJIT, LuaRocks, and Modules

This repository contains a `Dockerfile` to build a custom Nginx image with LuaJIT, LuaRocks, and several Nginx modules, including `ngx_http_geoip2_module`, `lua-nginx-module`, and `stream-lua-nginx-module`. It also includes `certbot`, `bash`, `tzdata`, and `logrotate` for a more complete server environment.

## Features

*   **Nginx:** Configurable version (default: 1.29.3)
*   **LuaJIT:** High-performance Just-In-Time compiler for Lua.
*   **LuaRocks:** Package manager for Lua modules.
*   **Nginx Modules:**
    *   `ngx_http_geoip2_module`: GeoIP2 module for Nginx.
    *   `lua-nginx-module`: Embed the Lua scripting language into Nginx.
    *   `stream-lua-nginx-module`: Embed the Lua scripting language into Nginx stream module.
*   **Lua Libraries:** `lua-resty-core` and `lua-resty-lrucache`.
*   **Utilities:** `certbot` (for SSL/TLS certificates), `bash`, `tzdata` (timezone set to Asia/Tokyo), and `logrotate`.
*   **Multi-stage Build:** Optimized for smaller final image size.

## Build Arguments

You can customize the Nginx and LuaRocks versions using build arguments:

*   `NGINX_VER`: Nginx version (default: `1.29.3`)
*   `LUAROCKS_VER`: LuaRocks version (default: `3.12.2`)

## How to Build

To build the Docker image, navigate to the directory containing the `Dockerfile` and run:

```bash
docker build -t my-nginx-lua .
```

To build with specific versions:

```bash
docker build -t my-nginx-lua:1.28.0 --build-arg NGINX_VER=1.28.0 --build-arg LUAROCKS_VER=3.12.0 .
```

## How to Run

After building the image, you can run a container from it.

### Basic Run

```bash
docker run -p 80:80 -p 443:443 --name my-nginx-container -d my-nginx-lua
```

### With Custom Nginx Configuration

You can mount your custom Nginx configuration files into the container. For example, if you have an `nginx.conf` and `nginx-https.conf` in your current directory:

```bash
docker run -p 80:80 -p 443:443 \
  -v ./nginx.conf:/etc/nginx/nginx.conf:ro \
  -v ./nginx-https.conf:/etc/nginx/nginx-https.conf:ro \
  --name my-nginx-container -d my-nginx-lua
```

**Note:** The `nginx-https.conf` file is referenced in the folder structure, so it's a good candidate for a custom configuration example.

## Exposed Ports

*   `80` (HTTP)
*   `443` (HTTPS)

## Timezone

The container's timezone is set to `Asia/Tokyo`.

## Certbot and Logrotate

`certbot` and `logrotate` are installed in the final image. You would typically configure `certbot` to obtain and renew SSL certificates and `logrotate` to manage Nginx access and error logs. The `logrotate` configuration is commented out in the `Dockerfile` but provides an example of how it could be set up.

```
