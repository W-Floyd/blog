FROM hugomods/hugo:exts AS hugo
COPY . /src
RUN hugo --minify

FROM nginx:alpine-slim
COPY --from=hugo /src/public /usr/share/nginx/html
COPY default.conf /etc/nginx/conf.d/default.conf
