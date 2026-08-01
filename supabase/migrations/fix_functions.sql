-- Run this script in Supabase SQL Editor to fix all function
-- schema-qualification issues without clashing with existing tables.

-- ============================================================
-- FIX: handle_new_user (migration 001)
-- ============================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, role)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data ->> 'full_name', 'User'),
        COALESCE(NEW.raw_user_meta_data ->> 'role', 'staff')
    );
    RETURN NEW;
END;
$$;

-- ============================================================
-- FIX: check_file_duplicate (migration 003)
-- ============================================================
CREATE OR REPLACE FUNCTION check_file_duplicate()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.files
        WHERE checksum = NEW.checksum
          AND uploaded_by = NEW.uploaded_by
          AND id != NEW.id
          AND deleted_at IS NULL
    ) THEN
        NEW.is_duplicate := TRUE;
    ELSE
        NEW.is_duplicate := FALSE;
    END IF;
    RETURN NEW;
END;
$$;

-- ============================================================
-- FIX: auto_assign_category (migration 003)
-- ============================================================
CREATE OR REPLACE FUNCTION auto_assign_category()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    doc_cat_id UUID;
    img_cat_id UUID;
    soft_cat_id UUID;
    arch_cat_id UUID;
BEGIN
    SELECT id INTO doc_cat_id FROM public.file_categories WHERE name = 'Documents' LIMIT 1;
    SELECT id INTO img_cat_id FROM public.file_categories WHERE name = 'Images' LIMIT 1;
    SELECT id INTO soft_cat_id FROM public.file_categories WHERE name = 'Software' LIMIT 1;
    SELECT id INTO arch_cat_id FROM public.file_categories WHERE name = 'Archives' LIMIT 1;

    IF NEW.category_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    CASE
        WHEN NEW.type IN ('application/pdf', 'application/msword',
             'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
             'application/vnd.ms-excel',
             'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
             'text/plain', 'text/csv') THEN
            NEW.category_id := doc_cat_id;
        WHEN NEW.type LIKE 'image/%' THEN
            NEW.category_id := img_cat_id;
        WHEN NEW.type IN ('application/zip', 'application/x-rar-compressed',
             'application/x-7z-compressed') THEN
            NEW.category_id := arch_cat_id;
        ELSE
            NEW.category_id := soft_cat_id;
    END CASE;

    RETURN NEW;
END;
$$;

-- ============================================================
-- FIX: log_file_action (migration 003)
-- ============================================================
CREATE OR REPLACE FUNCTION log_file_action()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details)
    VALUES (
        COALESCE(NEW.uploaded_by, auth.uid()),
        TG_ARGV[0]::text,
        'file',
        NEW.id,
        jsonb_build_object(
            'file_name', NEW.name,
            'file_type', NEW.type,
            'file_size', NEW.size,
            'category_id', NEW.category_id
        )
    );
    RETURN NEW;
END;
$$;

-- ============================================================
-- FIX: search_files (migration 003) — new signature (requesting_user)
-- ============================================================
CREATE OR REPLACE FUNCTION search_files(search_query TEXT, requesting_user UUID)
RETURNS TABLE (
    id UUID,
    name TEXT,
    type TEXT,
    category_name TEXT,
    size BIGINT,
    uploaded_by_name TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.id,
        f.name,
        f.type,
        fc.name AS category_name,
        f.size,
        p.full_name AS uploaded_by_name,
        f.created_at
    FROM public.files f
    LEFT JOIN public.file_categories fc ON f.category_id = fc.id
    LEFT JOIN public.profiles p ON f.uploaded_by = p.id
    WHERE f.deleted_at IS NULL
      AND (
          f.name ILIKE '%' || search_query || '%'
          OR fc.name ILIKE '%' || search_query || '%'
          OR f.type ILIKE '%' || search_query || '%'
      )
      AND (
          f.uploaded_by = requesting_user
          OR EXISTS (
              SELECT 1 FROM public.profiles
              WHERE id = requesting_user AND role = 'admin'
          )
      )
    ORDER BY f.created_at DESC;
END;
$$;

-- ============================================================
-- FIX: get_dashboard_stats (migration 003) — new signature (requesting_user)
-- ============================================================
CREATE OR REPLACE FUNCTION get_dashboard_stats(requesting_user UUID)
RETURNS TABLE (
    total_files BIGINT,
    total_storage_bytes BIGINT,
    files_this_week BIGINT,
    categories_count BIGINT,
    recent_backups BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    is_admin BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = requesting_user AND role = 'admin'
    ) INTO is_admin;

    RETURN QUERY
    SELECT
        (SELECT COUNT(*) FROM public.files WHERE deleted_at IS NULL AND (is_admin OR uploaded_by = requesting_user))::BIGINT,
        (SELECT COALESCE(SUM(size), 0) FROM public.files WHERE deleted_at IS NULL AND (is_admin OR uploaded_by = requesting_user))::BIGINT,
        (SELECT COUNT(*) FROM public.files WHERE deleted_at IS NULL AND (is_admin OR uploaded_by = requesting_user) AND created_at >= NOW() - INTERVAL '7 days')::BIGINT,
        (SELECT COUNT(*) FROM public.file_categories)::BIGINT,
        (SELECT COUNT(*) FROM public.backup_logs WHERE status = 'completed' AND started_at >= NOW() - INTERVAL '30 days')::BIGINT;
END;
$$;

-- ============================================================
-- FIX: restore_from_backup (migration 004)
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
    SELECT snapshot INTO snap FROM public.backup_logs WHERE id = backup_id;
    IF snap IS NULL THEN
        RETURN QUERY SELECT 0, 0, 'Backup not found or has no snapshot'::TEXT;
        RETURN;
    END IF;

    FOR rec IN SELECT * FROM jsonb_array_elements(snap)
    LOOP
        IF EXISTS (
            SELECT 1 FROM public.files
            WHERE checksum = rec->>'checksum'
              AND uploaded_by = (rec->>'uploaded_by')::UUID
              AND deleted_at IS NULL
        ) THEN
            skipped_count := skipped_count + 1;
        ELSE
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

-- ============================================================
-- FIX: add snapshot column if missing (migration 004)
-- ============================================================
ALTER TABLE backup_logs
    ADD COLUMN IF NOT EXISTS snapshot JSONB;
