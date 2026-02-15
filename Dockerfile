# syntax=docker/dockerfile:1

############################
# 1. Frontend Build
############################
FROM node:22-alpine AS frontend-build

ENV NODE_OPTIONS="--max-old-space-size=4096"
WORKDIR /app

RUN apk add --no-cache git

COPY package.json package-lock.json ./
RUN npm ci --force

COPY . .
ARG BUILD_HASH=dev
ENV APP_BUILD_HASH=${BUILD_HASH}

RUN npm run build


############################
# 2. Backend Runtime
############################
FROM python:3.11-slim-bookworm

ENV PYTHONUNBUFFERED=1
ENV PORT=8080
ENV ENV=prod
ENV DOCKER=true

# --- Security / Privacy / No Local Models ---
ENV SCARF_NO_ANALYTICS=true
ENV DO_NOT_TRACK=true
ENV ANONYMIZED_TELEMETRY=false

WORKDIR /app/backend

# User-Setup
ARG UID=0
ARG GID=0
ENV HOME=/root

RUN if [ $UID -ne 0 ]; then \
    if [ $GID -ne 0 ]; then addgroup --gid $GID app; fi; \
    adduser --uid $UID --gid $GID --home $HOME --disabled-password --no-create-home app; \
    fi

# System-Abhängigkeiten
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git build-essential pandoc gcc netcat-openbsd curl jq \
    libmariadb-dev \
    python3-dev \
    ffmpeg libsm6 libxext6 zstd \
    && rm -rf /var/lib/apt/lists/*

# 1. Python-Abhängigkeiten via uv (Nutzt deine requirements.txt)
COPY backend/requirements.txt .
RUN pip3 install --no-cache-dir uv && \
    uv pip install --system -r requirements.txt --no-cache-dir

# 2. Backend-Code kopieren
COPY ./backend .

# 3. Frontend-Build kopieren
COPY --from=frontend-build /app/build /app/build
COPY --from=frontend-build /app/package.json /app/package.json
COPY --from=frontend-build /app/CHANGELOG.md /app/CHANGELOG.md

# Berechtigungen anpassen
RUN chown -R $UID:$GID /app $HOME
RUN chmod +x start.sh

EXPOSE 8080

HEALTHCHECK CMD curl --silent --fail http://localhost:${PORT}/health | jq -ne 'input.status == true' || exit 1

# Start-Kommando
CMD ["bash", "start.sh"]