# --- Stage 1: install production dependencies only (no nodemon, no dev tools).
# --ignore-scripts: packages may not run their own install scripts (none needed here).
FROM node:14-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force

# --- Stage 2: the image that ships: Node, the app, prod dependencies
FROM node:14-alpine
WORKDIR /app

# Tells the app and its libraries to run in production mode
ENV NODE_ENV=production

# Dependencies from the build stage, then the source
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Remove npm: the container runs `node server.js` and never needs the package
# manager. This drops npm's own vulnerable dependencies from the image.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx

# Run as the image's built-in non-root user (uid 1000), not root
USER node

# The service listens on this port (overridden by the PORT env var)
EXPOSE 3001

# Start the server directly. nodemon (a dev tool) is not in the image.
CMD ["node", "server.js"]
