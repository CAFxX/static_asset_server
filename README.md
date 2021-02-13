# Static asset server

This repository contains a set of tools to generate static asset server container images, i.e. container images containing an HTTP server that returns optimized static assets.

The [HTTP server](cmd/server/main.go) is written in go and supports content type and content encoding negotiation. It expects static assets to be under a root directory, containing the original assets and the optimized variants of each asset, as well as an index file (`alt_path.json`) that defines the relationships (e.g. alternate content type or content encoding) between variants of each asset. The server always returns to the client the smallest variant that the client supports, and supports revalidation/caching using the asset modification date.

The responsibility of generating the optimized static assets as well as the index file lies with the [`compress.sh`](compress.sh) script. This script relies on well-known utilities (e.g. brotli, zopfli, zstd, optipng, mozjpeg, cwebp, ...) to perform these tasks.

Currently the following optimizations are performed:

- PNG image files are optimized with optipng/zopflipng, and alternate versions are created in AVIF, WebP and JPEG format (the last one only if the PNG file contains no transparent pixels)
- JPEG image files are optimized with mozjpeg and their quality lowered to 85; alternate versions are created in AVIF and WebP format
- Other files are statically compressed with zopfli (gzip), brotli and zstandard (zstd)

## Usage

The simplest way to use this tool is the following:

1. Ensure you have Docker running
2. Place the static assets in the `webroot` directory
3. Run 
   ```bash
   docker build --tag static_asset_builder --file Dockerfile.builder . && \
   docker build . && \
   docker run -p 8080:8080 $(docker image ls --format '{{.ID}}' | head -1)
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
- Add lzma variants
- Add svg minification
- Add webp optimization
- Add avif optimization
- Add avif variant for webp assets
- Add heif variants for all image assets
- Add webp2 variants for all image assets
- Add gif optimization and variants (apng, webp)
- Add html minification
- Add js minification
- Add css minification
- Add json minification
- Write some tests
- Optionally embed assets in the server
- Support caching optimization results
- Use unique (guaranteed collision-free) file names for asset variants
