# Static asset server

This repository contains a ahead-of-time static asset optimization pipeline that generates a container image providing a standalone static asset server.

The optimization pipeline, whose responsibility is generating the optimized static assets as well as the index file, is implemented in the `compress.sh` script. This script relies on well-known utilities (e.g. brotli, zopfli, zstd, optipng, mozjpeg, cwebp, gifsicle, ...) to perform these tasks.

Currently the following optimizations are performed:

- PNG image files are optimized with optipng/zopflipng, and alternate versions are created in AVIF, WebP and JPEG format (the last one only if the PNG file contains no transparent pixels)
- JPEG image files are optimized with mozjpeg and their quality lowered to 85; alternate versions are created in AVIF and WebP format
- GIF image files are optimized with gifsicle, and alternate versions are created in WebP, APNG, PNG (when the image contains a single frame), and JPEG (when the image contains a single frame and no transparency)
- Other files are statically compressed with zopfli (gzip), brotli and zstandard (zstd)

The [standalone HTTP server](cmd/server/main.go) is written in Go (with `net/http`) and supports `Content-Type` and `Content-Encoding` negotiation. It expects the optimized static assets to be contained under a root directory, as well as the index file (`alt_path.json`) that lists the relationships (e.g. alternate content type or content encoding) between variants of each asset. The server always returns to the client the smallest variant that the client supports, and supports revalidation/caching using the asset modification date.

The server can optionally serve the static assets over HTTPS by providing the server image with a certificate and key in `/server.crt` and `/server.key` (it is recommended to mount these as secrets when the container is started, e.g. via Docker [bind mounts](https://docs.docker.com/storage/bind-mounts/) or via Kubernetes [secrets](https://kubernetes.io/docs/concepts/configuration/secret/)).

The server image is based on [`gcr.io/distroless/static:nonroot`](https://github.com/GoogleContainerTools/distroless): as such it contains no shell or other binaries apart from the standalone HTTP server above.

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

   Please note that the second step is when asset optimization is performed and may take quite some time depending on how many static assets are present in `webroot`; if you want to speed up this step (at the expense of the compression ratio) you can replace `docker build .` with `docker build --build-arg compression=LOW .`
4. The static asset server should now be running on [localhost:8080](http://localhost:8080) (if you have file `webroot/foo/bar.htm` it should be served as [localhost:8080/foo/bar.htm](http://localhost:8080/foo/bar.htm))

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
- Add AVIF variant for WebP and GIF assets
- Add HEIF (`image/heif`) variants for image assets
- Add JPEG-XL (`image/jxl`) variants for image assets
- Add WebP2 variants for image assets
- Add HTML minification
- Add Javascript minification
- Add CSS minification
- Add JSON minification
- Write some tests
- Optionally embed assets in the server binary (`go:embed`)
- Support caching optimization results
- Use unique (guaranteed collision-free) file names for asset variants
- Provide an optional way to sort variants based on a "first contentful paint" criteria (important for image formats that support progressive decoding)
- Add `ETag` support
- Allow to request a specifc content-type or content-encoding via query parameters (e.g. for use with [`source`](https://developer.mozilla.org/en-US/docs/Learn/HTML/Multimedia_and_embedding/Responsive_images#use_modern_image_formats_boldly))
- Allow to request the original/unoptimized asset
- Allow to control optimization on a per-file basis
- Allow to disable optimization of certain formats (e.g. GIF files)
- Allow to disable creation of certain variants (e.g. HEIF variants)
- Automatic generation of resized variants (e.g. 1x/1.5x from 2x or from CSS-like selectors like `max-width: 640px`)
