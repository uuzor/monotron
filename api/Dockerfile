# Monoton Agentic Commerce API
# Multi-stage build for production

# =============================================================================
# Build stage
# =============================================================================
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy source
COPY tsconfig.json ./
COPY src ./src

# Build TypeScript
RUN npm run build

# =============================================================================
# Production stage
# =============================================================================
FROM node:20-alpine AS production

WORKDIR /app

# Install production dependencies only
COPY package*.json ./
RUN npm ci --only=production

# Copy built artifacts
COPY --from=builder /app/dist ./dist

# Environment variables (set at runtime)
ENV NODE_ENV=production
ENV PORT=3000

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Start the server
CMD ["node", "dist/index.js"]
