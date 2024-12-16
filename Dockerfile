ARG PRIVATE_KEY=0xf214f2b2cd398c806f84e317254e0f0b801d0643303237d97a22a48e01628897

FROM node:22-alpine AS base
WORKDIR /app
RUN corepack enable
COPY package.json yarn.lock tsconfig.json ./
COPY .yarn/ .yarn/
RUN yarn add hardhat dotenv wait-on
COPY hardhat.config.ts .

FROM base AS compile
ARG PRIVATE_KEY
COPY contracts/ contracts/
RUN yarn compile

FROM compile AS runtime
ENV PRIVATE_KEY=${PRIVATE_KEY}
# If only run hardhat node
# ENTRYPOINT [ "yarn", "hardhat", "node", "--hostname", "0.0.0.0" ]
# CMD [ "--port", "8545" ]

# Run hardhat node and then deploy our contracts
COPY scripts/ scripts/
COPY entrypoint.sh .
EXPOSE 8545
ENTRYPOINT [ "/bin/sh", "entrypoint.sh" ]
