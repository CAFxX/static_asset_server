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

    PNG_OPTIPNG_CMD="optipng -o5"
    PNG_ZOPFLIPNG_CMD="zopflipng --iterations=50 --filters=0me --lossy_transparent --lossy_8bit"
    PNG_WEBP_CMD="cwebp -m 6 -pre 4 -sharp_yuv -q 90"
    PNG_AVIF_CMD="avifenc -s 0"
    PNG_HEIF_CMD="heif-enc -q 45"
    PNG_JXL_CMD="cjxl -d 1 -s 9"

    JPG_WEBP_CMD="cwebp -m 6 -q 85"
    JPG_AVIF_CMD="avifenc -s 0"
    JPG_HEIF_CMD="heif-enc -q 40"
    JPG_JXL_CMD="cjxl -q 85 -s 9"

    GIF_CMD="gifsicle -O3"
    GIF_WEBP_CMD="gif2webp -m 6 -mixed -q 90"
    GIF_AVIF_CMD="convert -quality 90"
    GIF_APNG_CMD="gif2apng"
    GIF_OPTIPNG_CMD="optipng -o5"
    GIF_ZOPFLIPNG_CMD="zopflipng --iterations=50 --filters=0me --lossy_transparent --lossy_8bit"
    GIF_JPEG_CMD="cjpeg -quality 90 -optimize -progressive -sample 1x1"
    GIF_JXL_CMD="cjxl -d 1 -s 9"

    WEBP_AVIF_CMD="avifenc -s 0"
    WEBP_OPTIPNG_CMD="optipng -o5"
    WEBP_ZOPFLIPNG_CMD="zopflipng --iterations=50 --filters=0me --lossy_transparent --lossy_8bit"
    WEBP_JXL_CMD="cjxl -d 1 -s 9"
    
    SVG_CMD="svgo --multipass"
else
    GZIP_CMD="zopfli --i1 --gzip -c --"
    BROTLI_CMD="brotli -0 --keep --stdout --"
    ZSTD_CMD="zstd -1 -k -c --"
    ZSTD_DICT_CMD="zstd -1 -k -c -D /dict/zstd --"

    PNG_OPTIPNG_CMD="optipng -o0"
    PNG_ZOPFLIPNG_CMD="zopflipng -q --lossy_transparent --lossy_8bit"
    PNG_WEBP_CMD="cwebp -pre 4 -sharp_yuv -q 90"
    PNG_AVIF_CMD="avifenc"
    PNG_HEIF_CMD="heif-enc -q 45"
    PNG_JXL_CMD="cjxl -d 1"

    JPG_WEBP_CMD="cwebp -q 85"
    JPG_AVIF_CMD="avifenc"
    JPG_HEIF_CMD="heif-enc -q 40"
    JPG_JXL_CMD="cjxl -q 85"

    GIF_CMD="gifsicle -O1"
    GIF_WEBP_CMD="gif2webp -m 0 -mixed -q 90"
    GIF_AVIF_CMD="convert -quality 90"
    GIF_APNG_CMD="gif2apng"
    GIF_OPTIPNG_CMD="optipng -o0"
    GIF_ZOPFLIPNG_CMD="zopflipng -q --lossy_transparent --lossy_8bit"
    GIF_JPEG_CMD="cjpeg -quality 90 -optimize -progressive -sample 1x1"
    GIF_JXL_CMD="cjxl -d 1"
    
    WEBP_AVIF_CMD="avifenc"
    WEBP_OPTIPNG_CMD="optipng -o0"
    WEBP_ZOPFLIPNG_CMD="zopflipng --lossy_transparent --lossy_8bit"
    WEBP_JXL_CMD="cjxl -d 1"
    
    SVG_CMD="svgo"
fi

job_limit () { NJOBS=${1:-$(nproc)}
    # Check number of running jobs
    local joblist=($(jobs -rp))
    while (( ${#joblist[*]} >= NJOBS ))
    do
        echo "! job_limit ${#joblist[*]}"
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
    if [[ ! -f "$FILE_C" ]]; then
        return
    fi
    local FILE_SZ=$(wc -c <"$FILE")
    local FILE_C_SZ=$(wc -c <"$FILE_C")
    local ABSDIFF=$((FILE_SZ - FILE_C_SZ))
    local RELDIFF=$((100 - FILE_C_SZ * 100 / FILE_SZ))
    if (( ABSDIFF < MIN_ABSDIFF || RELDIFF < MIN_RELDIFF || FILE_C_SZ == 0 )); then
        rm "$FILE_C"
    else
        local MIMETYPE=$(file --brief --mime $FILE)
        touch -r "$FILE" "$FILE_C"
        alt_path /alt_path.db "/$FILE" "/$FILE_C" "$IMAGE" "$TYPE" "$FILE_C_SZ" "$MIMETYPE"
    fi
}

touch /mutex

foreach() { FILES=$1; FUNC=$2
    set +x
    for FILE in $FILES; do
        echo "> $FILE"
        (
            local out=$( ( set -x; "$FUNC" "$FILE" ) 2>&1 | sed -e 's/^/| /' | sed -e 's/\r/\r| /' )
            {
                flock $fd
                echo "< $FILE"
                echo "$out"
            } {fd}</mutex
        ) &
        job_limit
    done
    set -x
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

GIF_FILES=$(
    find . -type f \
        -iname '*.gif' \
        -size +1 \
        -printf '%P\n' \
)

WEBP_FILES=$(
    find . -type f \
        -iname '*.webp' \
        -size +1 \
        -printf '%P\n' \
)

SVG_FILES=$(
    find . -type f \
        -iname '*.svg' \
        -size +1 \
        -printf '%P\n' \
)

JSON_FILES=$(
    find . -type f \
        -iname '*.json' \
        -size +1 \
        -printf '%P\n' \
)

JS_FILES=$(
    find . -type f \
        -iname '*.js' \
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
        -not -iname '*.heif' \
        -not -iname '*.gz' \
        -not -iname '*.bz2' \
        -not -iname '*.zst' \
        -not -iname '*.br' \
        -not -iname '*.xz' \
        -not -iname '*.woff' \
        -not -iname '*.woff2' \
        -printf '%P\n' \
)

## optimize svg images

process_svg() { FILE=$1
    $SVG_CMD "$FILE"
}

foreach "$SVG_FILES" process_svg

## optimize gif images

process_gif() { FILE=$1
    $GIF_CMD -b "$FILE"

    $GIF_WEBP_CMD "$FILE" -o "$FILE.webp"
    validate "$FILE" "$FILE.webp" "image/webp" true

    #$GIF_AVIF_CMD "$FILE" "$FILE.avif"
    #validate "$FILE" "$FILE.avif" "image/avif" true

    $GIF_APNG_CMD "$FILE" "$FILE.apng"
    validate "$FILE" "$FILE.apng" "image/apng" true

    $GIF_JXL_CMD "$FILE" "$FILE.jxl"
    validate "$FILE" "$FILE.jxl" "image/jxl" true

    FRAMES=$(identify -format '%n ' "$FILE" | cut -f1 -d' ')
    if [ "$FRAMES" == "1" ]; then
        $GIF_OPTIPNG_CMD -out "$FILE.png" "$FILE"
        $GIF_ZOPFLIPNG_CMD "$FILE.png" "$FILE.zopflipng"
        [[ -f "$FILE.zopflipng" ]] && mv -f "$FILE.zopflipng" "$FILE.png"
        validate "$FILE" "$FILE.png" "image/png" true

        OPAQUE=$(identify -format '%[opaque]' "$FILE")
        if [ "$OPAQUE" == "true" ]; then
            convert "$FILE" pnm:- | $GIF_JPG_CMD -outfile "$FILE.jpg"
            validate "$FILE" "$FILE.jpg" "image/jpeg" true
        fi
    fi
}

foreach "$GIF_FILES" process_gif

## optimize jpeg images

process_jpeg() { FILE=$1
    $JPG_WEBP_CMD "$FILE" -o "$FILE.webp"
    $JPG_AVIF_CMD "$FILE" "$FILE.avif"
    $JPG_HEIF_CMD -o "$FILE.heif" "$FILE"
    $JPG_JXL_CMD "$FILE" "$FILE.jxl"

    QUALITY=$(identify -format '%[quality]' "$FILE")
    if (( QUALITY >= 88 )); then
        djpeg "$FILE" | cjpeg -quality 85 -optimize -progressive -outfile "$FILE.new"
        mv -f "$FILE.new" "$FILE" 
    else
        jpegtran -optimize -progressive -outfile "$FILE" "$FILE"
    fi

    validate "$FILE" "$FILE.webp" "image/webp" true
    validate "$FILE" "$FILE.avif" "image/avif" true
    validate "$FILE" "$FILE.heif" "image/heif" true
    validate "$FILE" "$FILE.jxl" "image/jxl" true
}

foreach "$JPEG_FILES" process_jpeg

## optimize png images

process_png() { FILE=$1
    $PNG_OPTIPNG_CMD "$FILE"
    $PNG_ZOPFLIPNG_CMD "$FILE" "$FILE.zopflipng"
    [[ -f "$FILE.zopflipng" ]] && mv -f "$FILE.zopflipng" "$FILE"

    $PNG_WEBP_CMD "$FILE" -o "$FILE.webp"
    validate "$FILE" "$FILE.webp" "image/webp" true

    $PNG_AVIF_CMD "$FILE" "$FILE.avif"
    validate "$FILE" "$FILE.avif" "image/avif" true

    $PNG_HEIF_CMD -o "$FILE.heif" "$FILE"
    validate "$FILE" "$FILE.heif" "image/heif" true

    $PNG_JXL_CMD "$FILE" "$FILE.jxl"
    validate "$FILE" "$FILE.jxl" "image/jxl" true

    OPAQUE=$(identify -format '%[opaque]' "$FILE")
    if [ "$OPAQUE" == "true" ]; then
        convert "$FILE" pnm:- | cjpeg -quality 90 -optimize -progressive -sample 1x1 -outfile "$FILE.jpg"
        validate "$FILE" "$FILE.jpg" "image/jpeg" true
    fi
}

foreach "$PNG_FILES" process_png

## optimize webp images

process_webp() { FILE=$1
    # `identify -format %n` does not work correctly for webp
    FRAMES=$(webpinfo -quiet -summary "$FILE" | grep 'Number of frames:' | cut -f4 -d' ')
    if [ "$FRAMES" == "1" ]; then
        dwebp "$FILE" -o "$FILE.png"
        $WEBP_OPTIPNG_CMD "$FILE.png"
        $WEBP_ZOPFLIPNG_CMD "$FILE.png" "$FILE.zopflipng"
        [[ -f "$FILE.zopflipng" ]] && mv -f "$FILE.zopflipng" "$FILE.png"
        
        # we currently can't yet generate animated AVIF
        # we use the PNG because avifenc can not read webp
        $WEBP_AVIF_CMD "$FILE.png" "$FILE.avif"
        validate "$FILE" "$FILE.avif" "image/avif" true

        validate "$FILE" "$FILE.png" "image/png" true

        $WEBP_JXL_CMD "$FILE" "$FILE.jxl"
        validate "$FILE" "$FILE.jxl" "image/jxl" true

        OPAQUE=$(identify -format '%[opaque]' "$FILE")
        if [ "$OPAQUE" == "true" ]; then
            convert "$FILE" pnm:- | cjpeg -quality 85 -optimize -progressive -outfile "$FILE.jpg"
            validate "$FILE" "$FILE.jpg" "image/jpeg" true
        fi
    fi
}

foreach "$WEBP_FILES" process_webp

## minify json files

minify_json() { FILE=$1
    jq -c -S <"$FILE" >"$FILE.jq" || rm -f "$FILE.jq"
    mv -f "$FILE.jq" "$FILE"
}

foreach "$JSON_FILES" minify_json

## minify js files

minify_js() { FILE=$1
    uglifyjs --compress --mangle -o "$FILE.minifyjs" -- "$FILE" || rm -f "$FILE.minifyjs"
    mv -f "$FILE.minifyjs" "$FILE"
}

foreach "$JS_FILES" minify_js

## precompress uncompressed files

wait # some files that we need to compress may still be being worked on

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

for FILE in $COMPRESSIBLE_FILES; do
    check_file "$FILE"
done

mkdir /dict
#echo "$COMPRESSIBLE_FILES" >/filelist
#zstd --train -o /dict/zstd --maxdict=10000 --filelist=/filelist

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

    #local FILE_ZSTD="$FILE.zst-dict"
    #$ZSTD_DICT_CMD "$FILE" > "$FILE_ZSTD"
    #validate "$FILE" "$FILE_ZSTD" zstd-dict false
}

foreach "$COMPRESSIBLE_FILES" compress_file

wait # until all files are processed

alt_path /alt_path.db >/alt_path.json

jq </alt_path.json
