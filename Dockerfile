FROM static_asset_builder AS build
WORKDIR /
ARG compression=HIGH

COPY compress.sh /
COPY webroot /webroot
RUN rm -f /webroot/.gitkeep
RUN COMPRESSION=$compression ASSET_DIR=/webroot /compress.sh

COPY cmd/server /cmd/server
RUN (cd /cmd/server && go get && CGO_ENABLED=0 go build -o /server)


FROM alpine AS server
WORKDIR /
COPY --from=build /webroot /webroot
COPY --from=build /dict /dict
COPY --from=build /alt_path.json /alt_path.json
COPY --from=build /server /server

CMD /server /alt_path.json /webroot
