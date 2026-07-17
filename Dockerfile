# Production Dockerfile (Multi-Stage with BuildKit)
# syntax=docker/dockerfile:1.10
# ══ Stage 1: dependency resolver ══════════════════════════════════════
FROM python:3.13-slim AS deps

# Set pip to not cache unnecessarily
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Copy only requirements first — layer cache optimisation
COPY src/requirements.txt .

# Use BuildKit cache mount for pip — dramatically faster rebuilds
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --prefix=/install -r requirements.txt

# ══ Stage 2: runtime image ════════════════════════════════════════════
FROM python:3.13-slim AS runtime

# Security: run as non-root
RUN groupadd --gid 1000 appuser && \
    useradd --uid 1000 --gid appuser --shell /bin/bash --create-home appuser

ENV PYTHONPATH=/app \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Copy installed packages from deps stage
COPY --from=deps /install /usr/local

# Copy application source
COPY src/ .

# Switch to non-root user
USER appuser

# Expose port (documentation only)
EXPOSE 8000

# Health check at Docker level (belt and suspenders with K8s probes)
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

# Entrypoint
CMD ["uvicorn", "main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--workers", "2", \
     "--log-config", "/dev/null"]