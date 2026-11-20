# syntax=docker/dockerfile:1

# ---- Stage 1: build ----------------------------------------------------------
# Install dependencies into a virtual environment. Build tools stay in this
# stage and never reach the final image.
FROM python:3.12-slim AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
# Copy requirements first so this layer is cached until dependencies change
COPY requirements.txt .
RUN pip install -r requirements.txt

# ---- Stage 2: test (CI only: docker build --target test) ---------------------
FROM build AS test
RUN pip install pytest
COPY . .
RUN pytest -q tests

# ---- Stage 3: runtime --------------------------------------------------------
FROM python:3.12-slim AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    PORT=8080
WORKDIR /app
# Run as a non-root user
RUN groupadd --system app && useradd --system --gid app --no-create-home app
COPY --from=build /opt/venv /opt/venv
COPY app.py .
ARG APP_VERSION=local
ENV APP_VERSION=${APP_VERSION}
USER app
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2).status == 200 else 1)"
CMD ["sh", "-c", "exec gunicorn --workers 2 --bind 0.0.0.0:${PORT} --access-logfile - app:app"]
