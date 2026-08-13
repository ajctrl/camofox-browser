FROM node:24-slim AS camofox-browser

# Pinned Camoufox version for reproducible builds
# Update these when upgrading Camoufox
ARG CAMOUFOX_VERSION=150.0.2
# GitHub tag release. The Linux asset releases differ by architecture for v150.
ARG CAMOUFOX_RELEASE=beta.25
ARG CAMOUFOX_X86_64_ASSET_RELEASE=alpha.26
ARG CAMOUFOX_X86_64_SHA256=b146b98b0c2c41023716feef36451f319a534309f72c54584a4b0b88670f510b
ARG CAMOUFOX_ARM64_ASSET_RELEASE=alpha.25
ARG CAMOUFOX_ARM64_SHA256=b2870af8cd99721d41bd48f0cce0f949449ab75364b80ee3d389bd35953ea213
ARG ARCH=x86_64

# Install dependencies for Camoufox (Firefox-based)
RUN apt-get update && apt-get install -y \
    # Firefox dependencies
    libgtk-3-0 \
    libdbus-glib-1-2 \
    libxt6 \
    libasound2 \
    libx11-xcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6 \
    # Mesa OpenGL/EGL for WebGL support (software rendering via llvmpipe)
    # Without these, Firefox cannot create WebGL contexts -- a major bot detection signal
    libegl1-mesa \
    libgl1-mesa-dri \
    libgbm1 \
    # Xvfb virtual display -- runs Camoufox as if on a real desktop (better anti-detection)
    xvfb \
    # Fonts
    fonts-liberation \
    fonts-noto-color-emoji \
    fontconfig \
    # Utils
    ca-certificates \
    curl \
    unzip \
    # yt-dlp runtime dependency
    python3-minimal \
    && rm -rf /var/lib/apt/lists/*

# Pre-bake Camoufox browser binary into image (downloaded at build time)
# Note: unzip returns exit code 1 for warnings (Unicode filenames), so we use || true and verify
RUN set -eux; \
    case "${ARCH}" in \
      x86_64) CAMOUFOX_ASSET_RELEASE="${CAMOUFOX_X86_64_ASSET_RELEASE}"; CAMOUFOX_SHA256="${CAMOUFOX_X86_64_SHA256}" ;; \
      arm64)  CAMOUFOX_ASSET_RELEASE="${CAMOUFOX_ARM64_ASSET_RELEASE}"; CAMOUFOX_SHA256="${CAMOUFOX_ARM64_SHA256}" ;; \
      *) echo "Unsupported arch: ${ARCH}" && exit 1 ;; \
    esac; \
    mkdir -p /root/.cache/camoufox; \
    curl -fSL "https://github.com/daijro/camoufox/releases/download/v${CAMOUFOX_VERSION}-${CAMOUFOX_RELEASE}/camoufox-${CAMOUFOX_VERSION}-${CAMOUFOX_ASSET_RELEASE}-lin.${ARCH}.zip" \
      -o /tmp/camoufox.zip; \
    echo "${CAMOUFOX_SHA256}  /tmp/camoufox.zip" | sha256sum -c -; \
    (unzip -q /tmp/camoufox.zip -d /root/.cache/camoufox || true); \
    rm /tmp/camoufox.zip; \
    chmod -R 755 /root/.cache/camoufox; \
    echo "{\"version\":\"${CAMOUFOX_VERSION}\",\"release\":\"${CAMOUFOX_ASSET_RELEASE}\"}" > /root/.cache/camoufox/version.json; \
    test -f /root/.cache/camoufox/camoufox-bin && echo "Camoufox installed successfully"

# Install yt-dlp for YouTube transcript extraction (no browser needed)
RUN curl -L -o /usr/local/bin/yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" \
    && chmod 755 /usr/local/bin/yt-dlp

WORKDIR /app

COPY package.json package-lock.json ./
COPY scripts/ ./scripts/
RUN npm ci --omit=dev

COPY server.js ./
COPY camofox.config.json ./
COPY lib/ ./lib/
COPY plugins/ ./plugins/
COPY scripts/ ./scripts/

# Install default plugin dependencies (apt packages + post-install hooks)
RUN sh scripts/install-plugin-deps.sh

ENV NODE_ENV=production
ENV CAMOFOX_PORT=9377

EXPOSE 9377

CMD ["sh", "-c", "node --max-old-space-size=${MAX_OLD_SPACE_SIZE:-128} server.js"]

# Optional: rebuild plugin deps after adding third-party plugins
# Usage: docker build --target with-plugins -t camofox-browser .
FROM camofox-browser AS with-plugins
COPY plugins/ ./plugins/
COPY camofox.config.json ./
COPY scripts/install-plugin-deps.sh /tmp/install-plugin-deps.sh
RUN /tmp/install-plugin-deps.sh && rm /tmp/install-plugin-deps.sh
