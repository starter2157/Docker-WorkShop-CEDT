# syntax=docker/dockerfile:1.7

# =============================================================================
# Builder stage — installs production dependencies only, on a fresh Node base.
# =============================================================================

# step-4a: pinned base image, stage named "builder".
FROM node:20.11-slim AS builder
#   Do NOT use `node:latest` — we want reproducible builds across the cohort.

WORKDIR /app

# step-4b: copy the manifests first so the install layer caches on lockfile changes.
#   `npm update proxy-addr` pulls express's transitive proxy-addr from 2.0.7 to
#   2.0.8 (CVE-2026-90711, CRITICAL). It stays inside express's own `~2.0.7`
#   range, so nothing under app/ has to change — the bump lives in this layer.
COPY app/package.json app/package-lock.json ./
RUN npm ci --omit=dev \
 && npm update proxy-addr --omit=dev

# step-4c: copy the rest of the app source into /app.
COPY app/ ./

# =============================================================================
# Runtime stage — slim final image. Nothing from builder's caches leaks in.
# =============================================================================

# step-4d: same tag as step-4a for consistency.
FROM node:20.11-slim

WORKDIR /app

# Keep the pinned base but carry no known CRITICALs (AC-08):
#   - apt upgrade picks up Debian security fixes for libgnutls30 and perl-base,
#     which the Feb-2024 base image predates.
#   - npm is dropped: the container's entrypoint is plain `node`, and npm's
#     bundled tar 6.2.0 carries CVE-2026-59873.
RUN apt-get update \
 && apt-get upgrade -y \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# step-4e: copy the fully-installed app from the builder stage.
COPY --from=builder /app /app

ENV NODE_ENV=production
EXPOSE 3000

# step-4f: probe /health with a Node one-liner — node:20.11-slim has no curl/wget.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
CMD node -e "require('http').get('http://localhost:3000/health', r => process.exit(r.statusCode===200?0:1)).on('error', () => process.exit(1))"

# step-4g: container start command.
CMD ["node", "src/index.js"]
