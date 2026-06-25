FROM ghcr.io/gohugoio/hugo:v0.163.3 AS hugo
COPY --chown=hugo:hugo . /src
WORKDIR /src
RUN hugo --minify

FROM nginx:alpine-slim
COPY --from=hugo /src/public /usr/share/nginx/html
COPY default.conf /etc/nginx/conf.d/default.conf
