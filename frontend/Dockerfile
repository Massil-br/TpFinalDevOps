FROM nginx:alpine

RUN rm /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/conf.d/default.conf

COPY app.js /usr/share/nginx/html
COPY index.html /usr/share/nginx/html
COPY styles.css /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]