# docker build --tag static_asset_builder --file Dockerfile.builder .

FROM ubuntu:rolling
WORKDIR /

RUN echo 'APT::Acquire::Retries "3";' >/etc/apt/apt.conf.d/80-retries && \
    apt-get update && \
    apt-get install -y zopfli brotli zstd xz-utils optipng webp imagemagick gif2apng gifsicle \
                       cmake autoconf automake libtool nasm ninja-build make pkg-config git libpng-dev libjpeg-dev \
                       golang \
                       jq npm

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

RUN npm install -g svgo uglify-js

COPY cmd/alt_path /cmd/alt_path
RUN (cd /cmd/alt_path && go get && go build -o /usr/local/bin/alt_path)

COPY compress.sh /
