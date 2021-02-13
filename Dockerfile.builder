# docker build --tag static_asset_builder --file Dockerfile.builder .

FROM ubuntu:rolling
WORKDIR /

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

COPY cmd/alt_path /cmd/alt_path
RUN (cd /cmd/alt_path && go get && CGO_ENABLED=0 go build -o /usr/local/bin/alt_path)

COPY compress.sh /
