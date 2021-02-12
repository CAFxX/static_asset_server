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

#FROM nginx
#COPY --from=build /webroot /usr/share/nginx/html
#COPY --from=build /dict /usr/share/nginx/html/.dictionary
#COPY --from=build /alt_path.json /etc/nginx/alt_path.json
#COPY nginx.conf /etc/nginx/conf.d/default.conf
#COPY nginx.babel.js /etc/nginx/nginx.js
#RUN bash -c 'echo -e "load_module modules/ngx_http_js_module.so;\n\n$(cat /etc/nginx/nginx.conf)" >/etc/nginx/nginx.conf'




