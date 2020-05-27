FROM klakegg/hugo:0.71.1-onbuild AS hugo

FROM nginx
COPY --from=hugo /target /usr/share/nginx/html
