ARG gopath_default=/tmp/build-golang

FROM bitnami/minideb:bullseye as BUILD

ARG gopath_default
ENV GOPATH=$gopath_default
ENV PATH=$GOPATH/bin:/opt/bitnami/go/bin:$PATH
WORKDIR $GOPATH/src/github.com/didi/rdebug
COPY . $GOPATH/src/github.com/didi/rdebug

# 设置国内的 APT 源
RUN echo "deb http://mirrors.tuna.tsinghua.edu.cn/debian/ bullseye main contrib non-free" > /etc/apt/sources.list && \
    echo "deb http://mirrors.tuna.tsinghua.edu.cn/debian/ bullseye-updates main contrib non-free" >> /etc/apt/sources.list && \
    echo "deb http://mirrors.tuna.tsinghua.edu.cn/debian/ bullseye-backports main contrib non-free" >> /etc/apt/sources.list && \
    echo "deb http://mirrors.tuna.tsinghua.edu.cn/debian-security bullseye-security main contrib non-free" >> /etc/apt/sources.list


#RUN mkdir -p $GOPATH/bin && bitnami-pkg install go-1.8.3-0 --checksum 557d43c4099bd852c702094b6789293aed678b253b80c34c764010a9449ff136
RUN apt-get update && \
    apt-get install -y curl wget gnupg2 ca-certificates golang-glide gcc g++&& \
    rm -rf /var/lib/apt/lists/*

RUN install_packages build-essential wget libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev

RUN mkdir -p $GOPATH/bin
RUN wget https://storage.googleapis.com/golang/go1.8.3.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.8.3.linux-amd64.tar.gz \
    && rm go1.8.3.linux-amd64.tar.gz \
    && ln -s /usr/local/go/bin/go /usr/bin/go

# 定义 NGINX 版本
ENV NGINX_VERSION=1.14.0

# 创建安装目录
RUN mkdir -p /opt/bitnami/nginx/ && \
    mkdir -p /tmp/nginx

# 下载并编译 NGINX
RUN cd /tmp/nginx && \
    wget http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
    tar -xzvf nginx-${NGINX_VERSION}.tar.gz && \
    cd nginx-${NGINX_VERSION} && \
    ./configure --prefix=/opt/bitnami/nginx \
                --conf-path=/opt/bitnami/nginx/nginx.conf \
                --error-log-path=/opt/bitnami/nginx/error.log \
                --http-log-path=/opt/bitnami/nginx/access.log \
                --with-pcre \
                --with-http_ssl_module && \
    make && \
    make install

RUN cd koala-libc && sh build.sh \
    && cd ../koala && sh build.sh vendor && sh build.sh && sh build.sh recorder

FROM bitnami/php-fpm:7.1-debian-8 as FPM

ARG gopath_default
ENV PATH=/opt/bitnami/nginx/sbin:/opt/bitnami/php/bin:/opt/bitnami/php/sbin:$PATH
WORKDIR /usr/local/var/koala
COPY ./php/midi /usr/local/var/midi
COPY --from=BUILD /opt/bitnami/nginx/sbin /opt/bitnami/nginx/sbin
COPY --from=BUILD /bitnami/nginx/conf /opt/bitnami/nginx/conf
COPY --from=BUILD $gopath_default/src/github.com/didi/rdebug/output/libs/*.so /usr/local/var/koala/
COPY --from=BUILD $gopath_default/src/github.com/didi/rdebug/output/libs/koala-replayer.so /usr/local/var/midi/res/replayer/
COPY ./composer.json /usr/local/var/midi/composer.json
COPY ./example/php/nginx.conf /opt/bitnami/nginx/conf
COPY ./example/php/index.php /usr/local/var/koala/index.php
COPY ./example/php/1548160113499755925-1158745 /usr/local/var/koala/1548160113499755925-1158745
COPY ./example/php/docker/start.sh /usr/local/var/koala/start.sh
COPY ./example/php/docker/supervisor.conf /usr/local/var/koala/supervisor.conf

RUN install_packages apt-utils git vim curl lsof procps ca-certificates sudo locales supervisor && \
    chmod 444 /usr/local/var/koala/*so && \
    addgroup nobody && \
    sed -i -e 's/\s*Defaults\s*secure_path\s*=/# Defaults secure_path=/' /etc/sudoers && \
        echo "nobody ALL=NOPASSWD: ALL" >> /etc/sudoers && \
    sed -i \
        -e "s/pm = ondemand/pm = static/g" \
        -e "s/^listen = 9000/listen = \/usr\/local\/var\/run\/php-fpm.sock/g" \
        -e "s/^;clear_env = no$/clear_env = no/" \
        /opt/bitnami/php/etc/php-fpm.d/www.conf && \
    sed -i \
        -e "s/user=daemon/user=nobody/g" \
        -e "s/^group=daemon/group=nobody/g" \
        -e "s/listen.owner=daemon/listen.owner=nobody/g" \
        -e "s/listen.group=daemon/listen.group=nobody/g" \
        /opt/bitnami/php/etc/common.conf

EXPOSE 9111

CMD ["./start.sh"]
