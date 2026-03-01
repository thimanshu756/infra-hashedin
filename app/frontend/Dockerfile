FROM python:3.11-slim

RUN addgroup --system appgroup && \
    adduser --system --ingroup appgroup appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request; \
  urllib.request.urlopen('http://localhost:3000/health')"

CMD ["gunicorn", \
     "--bind", "0.0.0.0:3000", \
     "--workers", "2", \
     "--timeout", "60", \
     "--access-logfile", "-", \
     "app:app"]
