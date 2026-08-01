-- ============================================================
-- CB Storage System for Integrated Computing Business Hub
-- MIGRATION 011 — AUTOMATED BACKUP VIA SUPABASE pg_cron
-- ============================================================
-- Moves the automated backup OUT of the web process and INTO the
-- database. On hosts like Render's free tier the web service sleeps,
-- which stopped the in-process APScheduler backups. With pg_cron the
-- database itself checks the saved schedule (system_settings) every
-- minute and snapshots files when a backup is due.

-- Run this file in the Supabase SQL Editor (or `supabase db push`).

-- ── 1. Enable pg_cron ─────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ── 2. The backup job: snapshot all active files ─────────────
-- Mirrors the old Python perform_backup('scheduled', ...) exactly:
-- honours system_settings.backup_schedule (mode interval|daily|disabled).
CREATE OR REPLACE FUNCTION public.run_automated_backup()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    settings      jsonb;
    mode          text;
    last_scheduled timestamptz;
    due           boolean := false;
    snapshot_data jsonb;
    file_count    int;
    total_size    bigint;
    log_id        uuid;
    admin_id      uuid;
BEGIN
    -- Load the saved schedule (fall back to a sensible default)
    SELECT value INTO settings FROM public.system_settings WHERE key = 'backup_schedule';
    IF settings IS NULL THEN
        settings := '{"mode":"daily","interval_minutes":30,"hour":2,"minute":0}'::jsonb;
    END IF;

    mode := settings->>'mode';
    IF mode IS NULL OR mode = 'disabled' THEN
        RETURN;
    END IF;

    -- When did we last take a scheduled snapshot?
    SELECT max(started_at) INTO last_scheduled
    FROM public.backup_logs WHERE type = 'scheduled' AND status = 'completed';

    IF mode = 'interval' THEN
        due := (last_scheduled IS NULL)
            OR (now() - last_scheduled >= make_interval(mins => GREATEST(1, COALESCE((settings->>'interval_minutes')::int, 30))));
    ELSE
        -- daily: run once per day after the configured time
        IF last_scheduled IS NOT NULL AND last_scheduled::date = current_date THEN
            due := false;
        ELSE
            due := now() >= date_trunc('day', now())
                + make_interval(hours => GREATEST(0, LEAST(23, COALESCE((settings->>'hour')::int, 2))))
                + make_interval(mins => GREATEST(0, LEAST(59, COALESCE((settings->>'minute')::int, 0))));
        END IF;
    END IF;

    IF NOT due THEN
        RETURN;
    END IF;

    -- Snapshot all active files (same shape the restore function expects)
    SELECT coalesce(jsonb_agg(jsonb_build_object(
               'id',           f.id,
               'name',         f.name,
               'type',         f.type,
               'category_id',  f.category_id,
               'size',         f.size,
               'storage_path', f.storage_path,
               'uploaded_by',  f.uploaded_by,
               'description',  f.description,
               'checksum',     f.checksum,
               'is_duplicate', f.is_duplicate,
               'created_at',   f.created_at
           ) ORDER BY f.created_at DESC), '[]'::jsonb)
    INTO snapshot_data
    FROM public.files f
    WHERE f.deleted_at IS NULL;

    file_count := jsonb_array_length(snapshot_data);
    IF file_count = 0 THEN
        RETURN;  -- nothing to back up
    END IF;

    SELECT coalesce(sum(size), 0) INTO total_size FROM public.files WHERE deleted_at IS NULL;

    INSERT INTO public.backup_logs (type, status, started_at, completed_at, file_count, size_bytes, snapshot, triggered_by)
    VALUES ('scheduled', 'completed', now(), now(), file_count, total_size, snapshot_data, NULL)
    RETURNING id INTO log_id;

    -- Audit trail (attribute to the first admin, if any)
    SELECT id INTO admin_id FROM public.profiles WHERE role = 'admin' ORDER BY created_at LIMIT 1;
    IF admin_id IS NOT NULL THEN
        INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details)
        VALUES (admin_id, 'backup', 'backup', log_id,
                jsonb_build_object('type', 'scheduled', 'file_count', file_count, 'total_size', total_size));
    END IF;
END;
$$;

-- ── 3. Idempotent cron-job installer (called by the backend on boot) ──
CREATE OR REPLACE FUNCTION public.ensure_backup_cron()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cb-automated-backup') THEN
        PERFORM cron.schedule('cb-automated-backup', '*/1 * * * *', 'select public.run_automated_backup()');
    END IF;
END;
$$;

-- ── 4. Let the backend (service_role) invoke them ─────────────
GRANT EXECUTE ON FUNCTION public.run_automated_backup() TO service_role;
GRANT EXECUTE ON FUNCTION public.ensure_backup_cron() TO service_role;

-- ── 5. Schedule it now (idempotent) ───────────────────────────
SELECT public.ensure_backup_cron();
