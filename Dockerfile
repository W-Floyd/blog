FROM ghcr.io/gohugoio/hugo:v0.164.0 AS hugo
COPY --chown=hugo:hugo . /src
WORKDIR /src
RUN hugo --minify

# Max-effort compression once here, instead of per request in the proxy.
FROM alpine AS compress
RUN apk add --no-cache brotli zstd mailcap
COPY --from=hugo /src/public /srv
RUN find /srv -type f -size +1k \
      -regex '.*\.\(html\|css\|js\|mjs\|xml\|svg\|json\|txt\|ico\|webmanifest\)' \
      -print0 | xargs -0 -n1 -P "$(nproc)" \
      sh -c 'brotli -Z -k "$1" && zstd --ultra -22 -q -k "$1" && gzip -9 -k "$1"' _

FROM scratch
COPY --from=compress /etc/mime.types /etc/mime.types
# Already stripped and static. A build with only the needed modules came out
# no smaller: caddytls pulls in the PKI stack regardless.
COPY --from=caddy:2.11.9-alpine /usr/bin/caddy /caddy
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=compress /srv /srv
ENV XDG_CONFIG_HOME=/config XDG_DATA_HOME=/data
EXPOSE 80
ENTRYPOINT ["/caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
