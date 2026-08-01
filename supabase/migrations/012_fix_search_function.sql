-- ============================================================
-- CB Storage System for Integrated Computing Business Hub
-- MIGRATION 012 — FIX search_files (ambiguous "id" reference)
-- ============================================================
-- Some databases have a stale search_files() body that raises
-- 42702 "column reference id is ambiguous" (a PL/pgSQL RETURNS
-- TABLE variable colliding with an unqualified column reference),
-- which made /api/files/search return 500.
--
-- This replaces the function with a fully-qualified body. Run it
-- in the Supabase SQL Editor (or `supabase db push`).

CREATE OR REPLACE FUNCTION public.search_files(search_query TEXT, requesting_user UUID)
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
          OR f.description ILIKE '%' || search_query || '%'
          OR fc.name ILIKE '%' || search_query || '%'
          OR f.type ILIKE '%' || search_query || '%'
          OR EXISTS (
              SELECT 1 FROM public.category_keywords ck
              WHERE ck.category_id = f.category_id
                AND ck.keyword ILIKE '%' || search_query || '%'
          )
      )
      AND (
          f.uploaded_by = requesting_user
          OR EXISTS (
              SELECT 1 FROM public.profiles p2
              WHERE p2.id = requesting_user AND p2.role = 'admin'
          )
      )
    ORDER BY f.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_files(TEXT, UUID) TO authenticated, service_role;
