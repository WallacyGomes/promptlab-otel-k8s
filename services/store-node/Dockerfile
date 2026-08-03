FROM node:22-alpine

WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
COPY package*.json ./
RUN npm install --omit=dev
COPY src ./src
COPY public ./public
USER app
EXPOSE 3000
CMD ["node","src/server.js"]
