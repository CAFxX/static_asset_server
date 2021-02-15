# Static asset server

This repository contains a ahead-of-time static asset optimization pipeline that generates a container image providing a standalone static asset server.

The optimization pipeline, whose responsibility is generating the optimized static assets as well as the index file, is implemented in the `compress.sh` script. This script relies on well-known utilities (e.g. brotli, zopfli, zstd, optipng, mozjpeg, cwebp, ...) to perform these tasks.

Currently the following optimizations are performed:

- PNG image files are optimized with optipng/zopflipng, and alternate versions are created in AVIF, WebP and JPEG format (the last one only if the PNG file contains no transparent pixels)
- JPEG image files are optimized with mozjpeg and their quality lowered to 85; alternate versions are created in AVIF and WebP format
- Other files are statically compressed with zopfli (gzip), brotli and zstandard (zstd)

The [standalone HTTP server](cmd/server/main.go) is written in Go (with `net/http`) and supports `Content-Type` and `Content-Encoding` negotiation. It expects the optimized static assets to be contained under a root directory, as well as the index file (`alt_path.json`) that lists the relationships (e.g. alternate content type or content encoding) between variants of each asset. The server always returns to the client the smallest variant that the client supports, and supports revalidation/caching using the asset modification date.

## Usage

The simplest way to use this tool is the following:

1. Ensure you have Docker running
2. Place the static assets in the `webroot` directory
3. Run

   ```bash
   docker build --tag static_asset_builder --file Dockerfile.builder . && \
   docker build . && \
   docker run -p 8080:80 $(docker image ls --format '{{.ID}}' | head -1)
   ```

   Please note that the second step may take quite some time depending on how many static assets are present in `webroot`
4. The static asset server should now be running on http://localhost:8080 (if you have file `webroot/foo/bar.htm` it should be served as http://localhost:8080/foo/bar.htm)

If you want to speed up the asset optimization step (at the expense of the compression ratio) you can replace `docker build .` with `docker build --build-arg compression=LOW .`

## Contributing

PRs are welcome. Some ideas for what to add:

- Make the baking process run in parallel
- Finish implementation of zstd dictionary support
- Add gzip/brotli dictionary support
- Add dictionary serving
- Add JPEG-XL `jxl` content-encoding variant
- Add LZMA content-encoding variants
- Add SVG minification
- Add WebP optimization
- Add AVIF optimization
- Add AVIF variant for WebP assets
- Add HEIF (`image/heif`) variants for image assets
- Add JPEG-XL (`image/jxl`) variants for image assets
- Add WebP2 variants for image assets
- Add GIF optimization and variants (APNG, WebP)
- Add HTML minification
- Add Javascript minification
- Add CSS minification
- Add JSON minification
- Write some tests
- Optionally embed assets in the server binary (`go:embed`)
- Support caching optimization results
- Use unique (guaranteed collision-free) file names for asset variants
- Provide an optional way to sort variants based on a "first contentful paint" criteria (important for image formats that support progressive decoding)
- Provide optional TLS support
- Add `ETag` support
