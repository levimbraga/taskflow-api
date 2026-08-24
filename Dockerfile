# ---- Estágio 1: dependências -------------------------------------------------
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- Estágio 2: imagem final -------------------------------------------------
FROM python:3.12-slim

LABEL org.opencontainers.image.title="TaskFlow API" \
      org.opencontainers.image.description="DevOps na Prática - PUCRS" \
      org.opencontainers.image.source="https://github.com/levimbraga/taskflow-api"

# Execução sem privilégios de root (boa prática de segurança em contêineres)
RUN useradd --create-home --uid 1000 appuser

COPY --from=builder /install /usr/local
WORKDIR /app
COPY --chown=appuser:appuser app/ ./app/

USER appuser
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health').status==200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
