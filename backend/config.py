import os
from dotenv import load_dotenv

load_dotenv()


class Config:
    SUPABASE_URL = os.getenv("SUPABASE_URL")
    SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY")
    SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
    STORAGE_BUCKET = "hub-storage"

    # Automated backup schedule (24h clock, UTC). Set BACKUP_SCHEDULE_ENABLED=false
    # to disable, or BACKUP_SCHEDULE_HOUR/MINUTE to pick the daily run time.
    BACKUP_SCHEDULE_ENABLED = os.getenv("BACKUP_SCHEDULE_ENABLED", "true").lower() == "true"
    BACKUP_SCHEDULE_HOUR = int(os.getenv("BACKUP_SCHEDULE_HOUR", "2"))
    BACKUP_SCHEDULE_MINUTE = int(os.getenv("BACKUP_SCHEDULE_MINUTE", "0"))
