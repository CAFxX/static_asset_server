# docker build --tag static_asset_builder --file Dockerfile.builder .

FROM ubuntu:rolling
WORKDIR /

RUN echo 'APT::Acquire::Retries "3";' >/etc/apt/apt.conf.d/80-retries && \
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
                       zopfli brotli zstd optipng webp imagemagick gif2apng gifsicle \
                       cmake autoconf automake libtool nasm ninja-build make pkg-config git libpng-dev libjpeg-dev \
                       golang \
                       jq npm \
                       x265 libx265-dev libde265-dev libaom-dev automake \
                       clang libwebp-dev libbrotli-dev

RUN git clone --single-branch --branch v4.0.3 --depth=1 https://github.com/mozilla/mozjpeg.git && \
    cd mozjpeg && \
    mkdir build && \
    cd build && \
    cmake -G"Unix Makefiles" ../ && \
    make -j`getconf NPROCESSORS_ONLN` install && \
    cd /usr/local/bin && \
    ln -s /opt/mozjpeg/bin/cjpeg && \
    ln -s /opt/mozjpeg/bin/djpeg && \
    ln -s /opt/mozjpeg/bin/jpegtran

RUN git clone --depth 1 https://github.com/AOMediaCodec/libavif.git && \
    cd libavif/ext/ && \
    ./aom.cmd && \
    cd .. && \
    mkdir build && \
    cd build && \
    cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DAVIF_CODEC_AOM=ON -DAVIF_LOCAL_AOM=ON -DAVIF_BUILD_APPS=ON ..  && \
    ninja && \
    cd /usr/local/bin && \
    ln -s /libavif/build/avifenc

RUN git clone --single-branch --branch v1.12.0 --depth=1 https://github.com/strukturag/libheif.git && \
    cd libheif && \
    ./autogen.sh && \
    ./configure --disable-go && \
    make -j`getconf NPROCESSORS_ONLN` && \
    cd /usr/local/bin && \
    ln -s /libheif/examples/heif-enc

RUN git clone --single-branch --branch v0.3.7 --depth=1 --recursive --shallow-submodules https://github.com/libjxl/libjxl.git && \
    cd libjxl && \
    mkdir build && \
    cd build && \
    export CC=clang CXX=clang++ && \
    cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF .. && \
    cmake --build . -- -j`getconf NPROCESSORS_ONLN` && \
    cd /usr/local/bin && \
    ln -s /libjxl/build/tools/cjxl && \
    ln -s /libjxl/build/tools/djxl

RUN npm install -g svgo uglify-js

COPY cmd/alt_path /cmd/alt_path
RUN (cd /cmd/alt_path && go get && go build -o /usr/local/bin/alt_path)

COPY compress.sh /
