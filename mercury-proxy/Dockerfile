ARG BUILD_FROM
FROM ${BUILD_FROM}

ARG MERCURY_PROXY_REF=master

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

WORKDIR /app

COPY requirements.txt /app/requirements.txt

RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r /app/requirements.txt \
    && /opt/venv/bin/pip install --no-cache-dir --no-deps \
        "mercury-proxy @ git+https://github.com/webtoucher/mercury-proxy.git@${MERCURY_PROXY_REF}"

ENV PATH="/opt/venv/bin:${PATH}"

COPY run.py /app/run.py

ENTRYPOINT ["python3", "-u", "/app/run.py"]
