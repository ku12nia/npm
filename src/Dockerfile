FROM node:22-alpine

WORKDIR /app

COPY package*.json ./

# Direct the installation to the NPM Proxy on the local Nexus instance
RUN npm config set registry http://host.docker.internal:8082/repository/npm-proxy/
RUN npm install

COPY . .

EXPOSE 3000
CMD ["npm", "start"]