# Gunicorn entry point for production hosting (Render / Railway / etc).
#
# IMPORTANT: run with a SINGLE worker so the APScheduler backup job starts
# exactly once:   gunicorn --workers 1 --bind 0.0.0.0:$PORT wsgi:app
from app import app, start_scheduler

start_scheduler()
