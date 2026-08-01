-- ============================================================
-- CB Storage System for Integrated Computing Business Hub
-- MIGRATION 014 — BACKUP RETENTION (keep last N)
-- ============================================================
-- Auto-deletes the oldest backup_logs entries so only the newest
-- max_backups snapshots are kept (applies to scheduled AND manual
-- backups). The limit is read from system_settings.backup_retention
-- and can be changed at runtime from the Backup page.
-- Run in the Supabase SQL Editor (or `supabase db push`).

-- ── 1. Retention function ────────────────────────────────────
-- Deletes every backup beyond the newest max_backups.
CREATE OR REPLACE FUNCTION public.run_backup_retention()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    settings jsonb;
    max_n    int;
BEGIN
    SELECT value INTO settings FROM public.system_settings WHERE key = 'backup_retention';
    IF settings IS NULL THEN
        settings := '{"max_backups": 10}'::jsonb;
    END IF;
    max_n := GREATEST(1, COALESCE((settings->>'max_backups')::int, 10));

    DELETE FROM public.backup_logs bl
    USING (
        SELECT id FROM public.backup_logs
        ORDER BY started_at DESC
        OFFSET max_n
    ) old
    WHERE bl.id = old.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.run_backup_retention() TO service_role;

-- ── 2. Wire retention into the automated backup job ─────────
-- (Re-created with the same RETURNS void signature, so
--  CREATE OR REPLACE is valid. Prunes right after each snapshot.)
CREATE OR REPLACE FUNCTION public.run_automated_backup()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    settings       jsonb;
    mode           text;
    last_scheduled timestamptz;
    due            boolean := false;
    snapshot_data  jsonb;
    file_count     int;
    total_size     bigint;
    log_id         uuid;
    admin_id       uuid;
BEGIN
    SELECT value INTO settings FROM public.system_settings WHERE key = 'backup_schedule';
    IF settings IS NULL THEN
        settings := '{"mode":"daily","interval_minutes":30,"hour":2,"minute":0}'::jsonb;
    END IF;

    mode := settings->>'mode';
    IF mode IS NULL OR mode = 'disabled' THEN
        RETURN;
    END IF;

    SELECT max(started_at) INTO last_scheduled
    FROM public.backup_logs WHERE type = 'scheduled' AND status = 'completed';

    IF mode = 'interval' THEN
        due := (last_scheduled IS NULL)
            OR (now() - last_scheduled >= make_interval(mins => GREATEST(1, COALESCE((settings->>'interval_minutes')::int, 30))));
    ELSE
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
        RETURN;
    END IF;

    SELECT coalesce(sum(size), 0) INTO total_size FROM public.files WHERE deleted_at IS NULL;

    INSERT INTO public.backup_logs (type, status, started_at, completed_at, file_count, size_bytes, snapshot, triggered_by)
    VALUES ('scheduled', 'completed', now(), now(), file_count, total_size, snapshot_data, NULL)
    RETURNING id INTO log_id;

    SELECT id INTO admin_id FROM public.profiles WHERE role = 'admin' ORDER BY created_at LIMIT 1;
    IF admin_id IS NOT NULL THEN
        INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details)
        VALUES (admin_id, 'backup', 'backup', log_id,
                jsonb_build_object('type', 'scheduled', 'file_count', file_count, 'total_size', total_size));
    END IF;

    PERFORM public.run_backup_retention();
END;
$$;

GRANT EXECUTE ON FUNCTION public.run_automated_backup() TO service_role;

-- ── 3. Seed the default retention setting ────────────────────
INSERT INTO public.system_settings (key, value)
VALUES ('backup_retention', '{"max_backups": 10}'::jsonb)
ON CONFLICT (key) DO NOTHING;
