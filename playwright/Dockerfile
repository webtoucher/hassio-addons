ARG BUILD_FROM
FROM ${BUILD_FROM}

WORKDIR /root

ARG PLAYWRIGHT_VERSION

RUN apt update -y && apt install nodejs npm -y \
    && npm install playwright@${PLAYWRIGHT_VERSION} \
    && npx playwright install

ENTRYPOINT npx playwright run-server --port 8585 --path /ws
