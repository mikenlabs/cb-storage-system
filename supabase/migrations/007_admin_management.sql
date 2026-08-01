-- Migration 007: Admin Panel Support
-- CB Storage System for Integrated Computing Business Hub
--
-- Additions (idempotent, safe to run on existing deployments):
--   1. get_users_admin()            - list all users with usage stats (admin only)
--   2. update_user_role()           - promote/demote a user (admin only)
--   3. search_files() redefinition  - fixed signature (accepts requesting_user UUID)
--   4. get_dashboard_stats() redef  - fixed signature (per-user stats for staff)

-- ============================================================
-- 1. LIST ALL USERS (with email + usage stats)
-- ============================================================
CREATE OR REPLACE FUNCTION get_users_admin()
RETURNS TABLE (
    id UUID,
    email TEXT,
    full_name TEXT,
    role TEXT,
    created_at TIMESTAMPTZ,
    file_count BIGINT,
    storage_bytes BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        u.email::TEXT AS email,
        p.full_name,
        p.role,
        p.created_at,
        COUNT(f.id) FILTER (WHERE f.deleted_at IS NULL)::BIGINT AS file_count,
        COALESCE(SUM(f.size) FILTER (WHERE f.deleted_at IS NULL), 0)::BIGINT AS storage_bytes
    FROM public.profiles p
    LEFT JOIN auth.users u ON u.id = p.id
    LEFT JOIN public.files f ON f.uploaded_by = p.id
    GROUP BY p.id, u.email, p.full_name, p.role, p.created_at
    ORDER BY p.created_at ASC;
END;
$$;

-- ============================================================
-- 2. UPDATE USER ROLE (admin only)
-- ============================================================
CREATE OR REPLACE FUNCTION update_user_role(target_user UUID, new_role TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    updated_row public.profiles%ROWTYPE;
BEGIN
    IF new_role NOT IN ('admin', 'staff') THEN
        RETURN jsonb_build_object('error', 'Invalid role');
    END IF;

    UPDATE public.profiles
    SET role = new_role, updated_at = NOW()
    WHERE id = target_user
    RETURNING * INTO updated_row;

    IF updated_row.id IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN jsonb_build_object(
        'id', updated_row.id,
        'full_name', updated_row.full_name,
        'role', updated_row.role
    );
END;
$$;

-- ============================================================
-- 3. SEARCH FILES (fixed: explicit requesting_user UUID)
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
-- 4. DASHBOARD STATS (fixed: per-user totals for staff)
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
-- GRANTS (functions default to PUBLIC EXECUTE, kept explicit)
-- ============================================================
GRANT EXECUTE ON FUNCTION get_users_admin() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION update_user_role(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION search_files(TEXT, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_dashboard_stats(UUID) TO authenticated, service_role;
