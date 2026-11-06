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
# Media gets its own layers, with fixed mtimes (Hugo writes fresh ones every
# build), so unchanged layers are skipped on push and pull. A closed year (one
# with a /srv-media/yYYYY COPY line below, read from this file) is one layer;
# everything else goes to 32 layers hashed by post (YYYY/MM/slug).
COPY --from=hugo /src/Dockerfile /tmp/Dockerfile
RUN years=$(sed -n 's#^COPY --from=compress /srv-media/y\([0-9]\{4\}\) .*#\1#p' /tmp/Dockerfile) \
    && cd /srv && mkdir /srv-media \
    && for d in $(seq 0 31) $(printf 'y%s ' $years); do mkdir /srv-media/$d; done \
    && find . -type f \
      -regex '.*\.\(avif\|webp\|png\|jpg\|jpeg\|JPG\|JPEG\|gif\|mp4\|webm\|woff\|woff2\|ttf\|otf\|pdf\)' \
    | sed 's#^\./##' | while IFS= read -r f; do \
        y=${f%%/*}; \
        case " $(echo $years) " in \
          *" $y "*) d=y$y ;; \
          *) case "$f" in [0-9][0-9][0-9][0-9]/*) key=$(echo "$f" | cut -d/ -f1-3) ;; *) key=$y ;; esac; \
             d=$(( $(printf %s "$key" | cksum | cut -d' ' -f1) % 32 )) ;; \
        esac; \
        mkdir -p "/srv-media/$d/$(dirname "$f")" && mv "$f" "/srv-media/$d/$f"; \
      done \
    && find /srv-media /srv -exec touch -h -d '1970-01-01 00:00:00' {} +

FROM scratch
COPY --from=compress /etc/mime.types /etc/mime.types
# Already stripped and static. A build with only the needed modules came out
# no smaller: caddytls pulls in the PKI stack regardless.
COPY --from=caddy:2.11.9-alpine /usr/bin/caddy /caddy
COPY Caddyfile /etc/caddy/Caddyfile
# Closed years: add the finished year here each January.
COPY --from=compress /srv-media/y2018 /srv
COPY --from=compress /srv-media/y2019 /srv
COPY --from=compress /srv-media/y2020 /srv
COPY --from=compress /srv-media/y2021 /srv
COPY --from=compress /srv-media/y2022 /srv
COPY --from=compress /srv-media/y2023 /srv
COPY --from=compress /srv-media/y2024 /srv
COPY --from=compress /srv-media/y2025 /srv
COPY --from=compress /srv-media/0 /srv
COPY --from=compress /srv-media/1 /srv
COPY --from=compress /srv-media/2 /srv
COPY --from=compress /srv-media/3 /srv
COPY --from=compress /srv-media/4 /srv
COPY --from=compress /srv-media/5 /srv
COPY --from=compress /srv-media/6 /srv
COPY --from=compress /srv-media/7 /srv
COPY --from=compress /srv-media/8 /srv
COPY --from=compress /srv-media/9 /srv
COPY --from=compress /srv-media/10 /srv
COPY --from=compress /srv-media/11 /srv
COPY --from=compress /srv-media/12 /srv
COPY --from=compress /srv-media/13 /srv
COPY --from=compress /srv-media/14 /srv
COPY --from=compress /srv-media/15 /srv
COPY --from=compress /srv-media/16 /srv
COPY --from=compress /srv-media/17 /srv
COPY --from=compress /srv-media/18 /srv
COPY --from=compress /srv-media/19 /srv
COPY --from=compress /srv-media/20 /srv
COPY --from=compress /srv-media/21 /srv
COPY --from=compress /srv-media/22 /srv
COPY --from=compress /srv-media/23 /srv
COPY --from=compress /srv-media/24 /srv
COPY --from=compress /srv-media/25 /srv
COPY --from=compress /srv-media/26 /srv
COPY --from=compress /srv-media/27 /srv
COPY --from=compress /srv-media/28 /srv
COPY --from=compress /srv-media/29 /srv
COPY --from=compress /srv-media/30 /srv
COPY --from=compress /srv-media/31 /srv
COPY --from=compress /srv /srv
ENV XDG_CONFIG_HOME=/config XDG_DATA_HOME=/data
EXPOSE 80
ENTRYPOINT ["/caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
