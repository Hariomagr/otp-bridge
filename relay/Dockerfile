# Relay image for Fly.io / Railway / any container host.
FROM node:22-alpine

WORKDIR /app

# Install prod deps against the lockfile for reproducible builds.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY server.js ./

ENV PORT=8080
EXPOSE 8080

CMD ["node", "server.js"]
