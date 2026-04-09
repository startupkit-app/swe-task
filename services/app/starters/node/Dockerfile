FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev 2>/dev/null || true
COPY . .
USER node
EXPOSE 8080
CMD ["node", "index.js"]
