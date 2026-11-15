ARG BUILD_FROM
FROM ${BUILD_FROM}

# The proxy itself is installed from its own repository: its code is not kept here.
ARG MERCURY_PROXY_REF=v2.0.0

ENV LANG=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUTF8=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        gcc \
        git \
        libc6-dev \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir \
        "mercury-proxy @ git+https://github.com/webtoucher/mercury-proxy.git@${MERCURY_PROXY_REF}"

ENV PATH="/opt/venv/bin:${PATH}"

COPY run.sh /app/run.sh
RUN chmod a+x /app/run.sh

ENTRYPOINT ["/app/run.sh"]
