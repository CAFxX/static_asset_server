# docker build --tag static_asset_builder --file Dockerfile.builder .

FROM ubuntu:devel
WORKDIR /
COPY compress.sh /
COPY alt_path.go /

RUN apt-get update && \
    apt-get install -y zopfli brotli zstd optipng webp imagemagick \
                       cmake autoconf automake libtool nasm make pkg-config git libpng-dev \
                       golang

RUN git clone --depth=1 https://github.com/mozilla/mozjpeg.git && \
    cd mozjpeg && \
    mkdir build && \
    cd build && \
    cmake -G"Unix Makefiles" ../ && \
    make -j`getconf NPROCESSORS_ONLN` install && \
    cd /usr/local/bin && \
    ln -s /opt/mozjpeg/bin/cjpeg && \
    ln -s /opt/mozjpeg/bin/djpeg && \
    ln -s /opt/mozjpeg/bin/jpegtran

RUN go get github.com/mattn/go-sqlite3 && \
    go build -o /usr/local/bin/alt_path /alt_path.go
