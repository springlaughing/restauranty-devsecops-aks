# --- Stage 1: build the static site with Node.
# --ignore-scripts: packages may not run their own install scripts (none needed here).
FROM node:25-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY . .

# The API base URL is baked into the build. On AKS the site and the API share
# one host, so this is the app's own domain. Override for other environments:
#   docker build --build-arg REACT_APP_SERVER_URL=http://localhost:80 ...
ARG REACT_APP_SERVER_URL=https://restauranty.aks.springlaughing.dev
ENV REACT_APP_SERVER_URL=$REACT_APP_SERVER_URL
RUN npm run build

# --- Stage 2: serve the static files with a non-root nginx
# nginx-unprivileged runs as a non-root user and listens on 8080.
FROM nginxinc/nginx-unprivileged:1.27-alpine

# Patch the OS packages the base image ships outdated (libssl, libcrypto,
# brotli). Done as root, then back to the non-root user the base image uses.
USER root
RUN apk --no-cache upgrade && rm -rf /var/cache/apk/*
USER 101

COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
