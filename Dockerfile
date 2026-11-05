# ========== 构建阶段：编译带指纹模块的 Nginx ==========
FROM debian:trixie AS builder

# 安装编译依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    patch \
    libpcre3-dev \
    zlib1g-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 版本参数（与你环境对齐）
ARG NGINX_VERSION=1.30.3
ARG OPENSSL_VERSION=3.5.6
ARG FINGERPRINT_BRANCH=ja4_fingerprint

WORKDIR /build

# 拉取对应版本源码
RUN git clone -b release-${NGINX_VERSION} --depth=1 https://github.com/nginx/nginx.git nginx
RUN git clone -b openssl-${OPENSSL_VERSION} --depth=1 https://github.com/openssl/openssl.git openssl
RUN git clone -b ${FINGERPRINT_BRANCH} --depth=1 https://github.com/hnakamur/nginx-ssl-fingerprint.git nginx-ssl-fingerprint

# 打补丁（若版本不兼容会给出警告，需手动调整补丁文件）
RUN patch -p1 -d openssl < nginx-ssl-fingerprint/patches/openssl.openssl-3.5.4.ja4.patch || \
    echo "===== Warning: openssl 补丁与 ${OPENSSL_VERSION} 可能不兼容 ====="
RUN patch -p1 -d nginx < nginx-ssl-fingerprint/patches/nginx-1.29.3.ja4.patch || \
    echo "===== Warning: nginx 补丁与 ${NGINX_VERSION} 可能不兼容 ====="

WORKDIR /build/nginx

# 执行 configure，完全复用你提供的编译参数，新增指纹模块与自定义 OpenSSL
RUN ./auto/configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/run/nginx.pid \
    --lock-path=/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-stream \
    --with-stream_realip_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-openssl=../openssl \
    --with-openssl-opt="no-apps no-legacy no-idea no-mdc2 no-rc5 no-zlib no-ssl3 no-tests no-ssl3-method enable-rfc3779 enable-cms no-capieng no-rdrand" \
    --add-module=../nginx-ssl-fingerprint \
    --with-cc-opt='-g -O2 -Werror=implicit-function-declaration -fstack-protector-strong -fstack-clash-protection -Wformat -Werror=format-security -fcf-protection -Wp,-D_FORTIFY_SOURCE=2 -fPIC' \
    --with-ld-opt='-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie'

# 编译并安装到临时目录
RUN make -j$(nproc)
RUN make DESTDIR=/tmp/nginx-install install


# ========== 运行阶段：最小化运行镜像 ==========
FROM debian:trixie-slim

# 安装运行时依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpcre3 \
    zlib1g \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 创建 nginx 用户与运行目录
RUN groupadd --system nginx && \
    useradd --system --gid nginx --home /nonexistent --shell /usr/sbin/nologin nginx && \
    mkdir -p /var/log/nginx /var/cache/nginx /run && \
    chown -R nginx:nginx /var/log/nginx /var/cache/nginx /run

# 从构建阶段复制产物
COPY --from=builder /tmp/nginx-install/etc/nginx /etc/nginx
COPY --from=builder /tmp/nginx-install/usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /tmp/nginx-install/usr/lib/nginx /usr/lib/nginx

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
