FROM --platform=$BUILDPLATFORM alpine:3.19 AS builder
WORKDIR /build

COPY index.html .

FROM --platform=$TARGETPLATFORM nginx:alpine
# fix : no match for platform in manifest (buildx build --platform linux/amd64,linux/arm64 -t yujie70338/static-web:Version .)

RUN touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid /var/cache/nginx /var/log/nginx /etc/nginx/conf.d

COPY --from=builder /build/index.html /usr/share/nginx/html/index.html

RUN sed -i 's/listen\(.*\)80;/listen 8080;/' /etc/nginx/conf.d/default.conf

EXPOSE 8080

USER nginx

CMD ["nginx", "-g", "daemon off;"]