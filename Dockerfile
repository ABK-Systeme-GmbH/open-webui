# syntax=docker/dockerfile:1

############################
# Frontend build
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
# Backend runtime
############################
FROM python:3.11-slim-bookworm

ENV PYTHONUNBUFFERED=1
ENV PORT=8080
ENV ENV=prod
ENV DOCKER=true

# --- Security / Privacy defaults ---
ENV SCARF_NO_ANALYTICS=true
ENV DO_NOT_TRACK=true
ENV ANONYMIZED_TELEMETRY=false

# --- Model access (extern only) ---
ENV OPENAI_API_KEY=""
ENV OPENAI_API_BASE_URL=""
ENV WEBUI_SECRET_KEY=""

# --- Plugins / Tools ready ---
# (Web search, email, APIs later)
ENV ENABLE_PLUGINS=true

WORKDIR /app/backend

# System deps (minimal but plugin-safe)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    git \
    ca-certificates \
    netcat-openbsd \
    pandoc \
    && rm -rf /var/lib/apt/lists/*

# Python deps
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Backend source
COPY backend/ .

# Built frontend
COPY --from=frontend-build /app/build /app/build
COPY --from=frontend-build /app/package.json /app/package.json
COPY --from=frontend-build /app/CHANGELOG.md /app/CHANGELOG.md

EXPOSE 8080

HEALTHCHECK CMD curl --silent --fail http://localhost:${PORT}/health | jq -ne 'input.status == true' || exit 1

CMD ["bash", "start.sh"]
