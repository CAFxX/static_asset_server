FROM cafxx/static_asset_builder:latest AS build
WORKDIR /
ARG compression=HIGH

COPY compress.sh /
RUN true # https://github.com/moby/moby/issues/37965
COPY webroot /webroot
RUN COMPRESSION=$compression ASSET_DIR=/webroot /compress.sh

COPY cmd/server /cmd/server
RUN (cd /cmd/server && go get && CGO_ENABLED=0 go build -o /server)


FROM gcr.io/distroless/static:nonroot AS server
WORKDIR /
COPY --from=build /webroot /webroot
COPY --from=build /dict /dict
COPY --from=build /alt_path.json /alt_path.json
COPY --from=build /server /bin/server

USER nonroot:nonroot
ENTRYPOINT ["/bin/server"]
