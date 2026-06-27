# NOTE: `make vendor` derives the self-hosted KaTeX version from this Hugo tag.
# After bumping it, re-run `make vendor` so the vendored CSS/fonts stay matched
# to the KaTeX engine this Hugo bundles (mismatch = silent styling breakage).
FROM ghcr.io/gohugoio/hugo:v0.163.3 AS hugo
COPY --chown=hugo:hugo . /src
WORKDIR /src
RUN hugo --minify

FROM nginx:alpine-slim
COPY --from=hugo /src/public /usr/share/nginx/html
COPY default.conf /etc/nginx/conf.d/default.conf
