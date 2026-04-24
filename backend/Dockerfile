FROM node:20-alpine AS deps

WORKDIR /app

COPY package*.json ./

RUN npm ci --omit=dev





FROM node:20-alpine AS final

RUN apk upgrade --no-cache

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules

COPY server.js .

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

USER appuser

EXPOSE 3001

CMD ["node","server.js"]