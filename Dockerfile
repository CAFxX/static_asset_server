FROM static_asset_builder AS build
WORKDIR /
COPY webroot /webroot
COPY cmd/server/main.go /main.go

RUN ASSET_DIR=/webroot /compress.sh
RUN CGO_ENABLED=0 go build -o /server /main.go


FROM alpine AS server
WORKDIR /
COPY --from=build /webroot /webroot
COPY --from=build /dict /dict
COPY --from=build /alt_path.json /alt_path.json
COPY --from=build /server /server

RUN /server /alt_path.json /webroot
