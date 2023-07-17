FROM klakegg/hugo:onbuild AS hugo

FROM nginx:alpine-slim
COPY --from=hugo /target /usr/share/nginx/html
COPY default.conf /etc/nginx/conf.d/default.conf