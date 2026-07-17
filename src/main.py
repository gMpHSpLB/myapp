# Create a minimal FastAPI application that CI will test
from fastapi import FastAPI
from fastapi.responses import JSONResponse
import os
import logging
import json

# Configure structured JSON logging
logging.basicConfig(
    level=getattr(logging, os.getenv("APP_LOG_LEVEL", "INFO")),
    format='{"time":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}'
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="myapp",
    version=os.getenv("APP_VERSION", "unknown"),
    docs_url="/docs" if os.getenv("APP_ENV") == "dev" else None
)

@app.get("/")
async def root():
    return {"app": "myapp", "env": os.getenv("APP_ENV", "unknown")}

@app.get("/health")
async def health():
    """Liveness probe endpoint"""
    return {"status": "alive"}

@app.get("/ready")
async def ready():
    """Readiness probe — checks dependencies"""
    # In production: check database connectivity, cache, etc.
    return {"status": "ready"}

@app.get("/metrics")
async def metrics():
    """Prometheus-compatible metrics endpoint placeholder"""
    return JSONResponse(
        content="# HELP myapp_requests_total Total requests\n",
        media_type="text/plain"
    )
