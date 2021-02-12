#!/usr/bin/env bash
set -eux

ASSET_DIR=${ASSET_DIR:-.}
MIN_RELDIFF=2 # percent (approx)
MIN_ABSDIFF=20 # bytes
COMPRESSION=${COMPRESSION:-HIGH}
if [ "$COMPRESSION" == "HIGH" ]; then
    GZIP_CMD="zopfli --i50 --gzip -c --"
    BROTLI_CMD="brotli --best --keep --stdout --"
    ZSTD_CMD="zstd -19 -k -c --"
    ZSTD_DICT_CMD="zstd -19 -k -c -D /dict/zstd --"
else
    GZIP_CMD="zopfli --i1 --gzip -c --"
    BROTLI_CMD="brotli --fast --keep --stdout --"
    ZSTD_CMD="zstd -1 -k -c --"
    ZSTD_DICT_CMD="zstd -1 -k -c -D /dict/zstd --"
fi

job_limit () { NJOBS=${1:-$(nproc)}
    # Check number of running jobs
    local joblist=($(jobs -rp))
    while (( ${#joblist[*]} >= NJOBS ))
    do
        # Wait for any job to finish
        local command='wait '${joblist[0]}
        for job in ${joblist[@]:1}
        do
            command+=' || wait '$job
        done
        eval $command
        joblist=($(jobs -rp))
    done
}

validate() { FILE=$1; FILE_C=$2; TYPE=$3; IMAGE=$4
    local FILE_SZ=$(wc -c <"$FILE")
    local FILE_C_SZ=$(wc -c <"$FILE_C")
    local ABSDIFF=$((FILE_SZ - FILE_C_SZ))
    local RELDIFF=$((100 - FILE_C_SZ * 100 / FILE_SZ))
    if (( ABSDIFF < MIN_ABSDIFF || RELDIFF < MIN_RELDIFF || FILE_C_SZ == 0 )); then
        rm "$FILE_C"
    else
        touch -r "$FILE" "$FILE_C"
        alt_path /alt_path.db "/$FILE" "/$FILE_C" "$IMAGE" "$TYPE" "$FILE_C_SZ"
    fi
}

check_file() { FILE=$1
    if [ ! -f "$FILE" ]; then echo "$FILE does not exist"; exit -1; fi

    local FILE_GZIP="$FILE.gz"
    if [ -f "$FILE_GZIP" ]; then echo "$FILE_GZIP already exists"; exit -2; fi
    local FILE_BROTLI="$FILE.br"
    if [ -f "$FILE_BROTLI" ]; then echo "$FILE_BROTLI already exists"; exit -3; fi
    local FILE_ZSTD="$FILE.zst"
    if [ -f "$FILE_ZSTD" ]; then echo "$FILE_ZSTD already exists"; exit -4; fi
    local FILE_ZSTD="$FILE.zst-dict"
    if [ -f "$FILE_ZSTD" ]; then echo "$FILE_ZSTD already exists"; exit -4; fi
}

compress_file() { FILE=$1
    local FILE_SZ=$(wc -c <"$FILE")
    if (( FILE_SZ < MIN_ABSDIFF )); then
        return
    fi

    local FILE_GZIP="$FILE.gz"
    $GZIP_CMD "$FILE" > "$FILE_GZIP"
    validate "$FILE" "$FILE_GZIP" gzip false

    local FILE_BROTLI="$FILE.br"
    $BROTLI_CMD "$FILE" > "$FILE_BROTLI"
    validate "$FILE" "$FILE_BROTLI" br false

    local FILE_ZSTD="$FILE.zst"
    $ZSTD_CMD "$FILE" > "$FILE_ZSTD"
    validate "$FILE" "$FILE_ZSTD" zstd false

    local FILE_ZSTD="$FILE.zst-dict"
    $ZSTD_DICT_CMD "$FILE" > "$FILE_ZSTD"
    validate "$FILE" "$FILE_ZSTD" zstd-dict false
}

## list files to be compressed

cd "$ASSET_DIR"

PNG_FILES=$(
    find . -type f \
        -iname '*.png' \
        -size +1 \
        -printf '%P\n' \
)

JPEG_FILES=$(
    find . -type f \
        \( -iname '*.jpg' -or -iname '*.jpeg' \) \
        -size +1 \
        -printf '%P\n' \
)

COMPRESSIBLE_FILES=$(
    find . -type f \
        -not -iname '*.gif' \
        -not -iname '*.png' \
        -not -iname '*.jpg' \
        -not -iname '*.jpeg' \
        -not -iname '*.webp' \
        -not -iname '*.gz' \
        -not -iname '*.bz2' \
        -not -iname '*.zst' \
        -not -iname '*.br' \
        -not -iname '*.xz' \
        -not -iname '*.woff' \
        -not -iname '*.woff2' \
        -printf '%P\n' \
)

## optimize jpeg images

for FILE in $JPEG_FILES; do
    echo "$FILE"

    cwebp -m 6 -q 85 "$FILE" -o "$FILE.webp"

    QUALITY=$(identify -format '%[quality]' "$FILE")
    if (( QUALITY >= 88 )); then
        djpeg "$FILE" | cjpeg -quality 85 -optimize -progressive -outfile "$FILE.new"
        mv -f "$FILE.new" "$FILE" 
    else
        jpegtran -optimize -progressive -outfile "$FILE" "$FILE"
    fi

    validate "$FILE" "$FILE.webp" "image/webp" true
done

## optimize png images

for FILE in $PNG_FILES; do
    echo "$FILE"
    optipng -o5 "$FILE"
    zopflipng "$FILE" "$FILE.zopflipng"
    [[ -f "$FILE.zopflipng" ]] && mv -f "$FILE.zopflipng" "$FILE"

    cwebp -m 6 -pre 4 -sharp_yuv -q 90 "$FILE" -o "$FILE.webp"
    validate "$FILE" "$FILE.webp" "image/webp" true

    #avifenc -s 0 "$FILE" "$FILE.avif"
    #validate "$FILE" "$FILE.avif" "image/avif" true

    OPAQUE=$(identify -format '%[opaque]' "$FILE")
    if [ "$OPAQUE" == "true" ]; then
        convert "$FILE" pnm:- | cjpeg -quality 90 -optimize -progressive -sample 1x1 -outfile "$FILE.jpg"
        validate "$FILE" "$FILE.jpg" "image/jpeg" true
    fi
done

## precompress uncompressed files

for FILE in $COMPRESSIBLE_FILES; do
    check_file "$FILE"
done

mkdir /dict
echo "$COMPRESSIBLE_FILES" >/filelist
zstd --train -o /dict/zstd --maxdict=10000 --filelist=/filelist

for FILE in $COMPRESSIBLE_FILES; do
    echo "$FILE"
    #( compress_file "$FILE" ) &
    #job_limit $(nproc)
    compress_file "$FILE"
done

alt_path /alt_path.db >/alt_path.json