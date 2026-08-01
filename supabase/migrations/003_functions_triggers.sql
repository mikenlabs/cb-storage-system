-- Migration 003: Functions and Triggers
-- CB Storage System for Integrated Computing Business Hub

-- ============================================================
-- DUPLICATE DETECTION
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

CREATE TRIGGER detect_duplicate_before_insert
    BEFORE INSERT ON files
    FOR EACH ROW
    EXECUTE FUNCTION check_file_duplicate();

-- ============================================================
-- AUTO-CATEGORIZATION BY FILE TYPE
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

CREATE TRIGGER auto_categorize_before_insert
    BEFORE INSERT ON files
    FOR EACH ROW
    EXECUTE FUNCTION auto_assign_category();

-- ============================================================
-- AUDIT LOGGING FUNCTION
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

CREATE TRIGGER log_file_upload
    AFTER INSERT ON files
    FOR EACH ROW
    EXECUTE FUNCTION log_file_action('upload');

CREATE TRIGGER log_file_delete
    AFTER UPDATE OF deleted_at ON files
    FOR EACH ROW
    WHEN (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL)
    EXECUTE FUNCTION log_file_action('delete');

-- ============================================================
-- SEARCH FUNCTION: FULL-TEXT SEARCH ON FILES
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
-- DASHBOARD STATS FUNCTION
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
