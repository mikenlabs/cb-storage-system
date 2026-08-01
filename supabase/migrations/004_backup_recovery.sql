-- Migration 004: Backup Snapshot and Restore Function
-- CB Storage System for Integrated Computing Business Hub

-- ============================================================
-- ADD SNAPSHOT COLUMN TO BACKUP_LOGS
-- ============================================================
ALTER TABLE backup_logs
    ADD COLUMN IF NOT EXISTS snapshot JSONB;

-- ============================================================
-- RESTORE FUNCTION: applies a backup snapshot
-- ============================================================
CREATE OR REPLACE FUNCTION restore_from_backup(backup_id UUID)
RETURNS TABLE (
    files_restored INT,
    duplicates_skipped INT,
    errors TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    snap JSONB;
    rec JSONB;
    restored_count INT := 0;
    skipped_count INT := 0;
    err_msg TEXT := '';
BEGIN
    -- Load the snapshot
    SELECT snapshot INTO snap FROM public.backup_logs WHERE id = backup_id;
    IF snap IS NULL THEN
        RETURN QUERY SELECT 0, 0, 'Backup not found or has no snapshot'::TEXT;
        RETURN;
    END IF;

    -- Iterate each file in the snapshot
    FOR rec IN SELECT * FROM jsonb_array_elements(snap)
    LOOP
        -- Check if file already exists (by checksum for same uploader)
        IF EXISTS (
            SELECT 1 FROM public.files
            WHERE checksum = rec->>'checksum'
              AND uploaded_by = (rec->>'uploaded_by')::UUID
              AND deleted_at IS NULL
        ) THEN
            skipped_count := skipped_count + 1;
        ELSE
            -- Restore the file record (undelete or re-insert)
            INSERT INTO public.files (
                name, type, category_id, size, storage_path,
                uploaded_by, description, checksum, is_duplicate,
                created_at, updated_at
            ) VALUES (
                rec->>'name',
                COALESCE(rec->>'type', 'application/octet-stream'),
                (rec->>'category_id')::UUID,
                (rec->>'size')::BIGINT,
                rec->>'storage_path',
                (rec->>'uploaded_by')::UUID,
                rec->>'description',
                rec->>'checksum',
                COALESCE((rec->>'is_duplicate')::BOOLEAN, FALSE),
                COALESCE((rec->>'created_at')::TIMESTAMPTZ, NOW()),
                NOW()
            );
            restored_count := restored_count + 1;
        END IF;
    END LOOP;

    RETURN QUERY SELECT restored_count, skipped_count, err_msg;
END;
$$;
