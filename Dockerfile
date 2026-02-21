FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends nano vim-tiny \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY monitor.py config.sample.json docker-entrypoint.sh /app/
RUN chmod +x /app/docker-entrypoint.sh

ENV MONITOR_DATA_DIR=/data
ENV MONITOR_CONFIG_PATH=/data/config.json
ENV MONITOR_STATE_PATH=/data/state.json
ENV MONITOR_INTERVAL_SEC=300

VOLUME ["/data"]

ENTRYPOINT ["/app/docker-entrypoint.sh"]
