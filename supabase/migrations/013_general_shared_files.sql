-- ============================================================
-- CB Storage System for Integrated Computing Business Hub
-- MIGRATION 013 — General (shared) files
-- ============================================================
-- Adds is_general to files. Any owner may share their own file
-- with all users (view/download only). search_files now returns
-- uploaded_by + is_general and includes general files in results.
-- Run in the Supabase SQL Editor (or `supabase db push`).

ALTER TABLE public.files ADD COLUMN IF NOT EXISTS is_general BOOLEAN NOT NULL DEFAULT false;

-- RLS: any authenticated user can view general files
DROP POLICY IF EXISTS "Users can view general files" ON public.files;
CREATE POLICY "Users can view general files"
    ON public.files FOR SELECT
    USING (is_general = true AND deleted_at IS NULL);

-- RLS: any owner can mark their own file as general (UPDATE already allows owners)
-- (Existing "Users can update own files" policy covers the is_general toggle.)

-- Rebuild search_files: include general files for all users, and expose
-- uploaded_by + is_general so the UI can split My/General sections.
CREATE OR REPLACE FUNCTION public.search_files(search_query TEXT, requesting_user UUID)
RETURNS TABLE (
    id UUID,
    name TEXT,
    type TEXT,
    category_name TEXT,
    size BIGINT,
    uploaded_by UUID,
    uploaded_by_name TEXT,
    is_general BOOLEAN,
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
        f.uploaded_by,
        p.full_name AS uploaded_by_name,
        f.is_general,
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
          OR f.is_general = true
          OR EXISTS (
              SELECT 1 FROM public.profiles p2
              WHERE p2.id = requesting_user AND p2.role = 'admin'
          )
      )
    ORDER BY f.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_files(TEXT, UUID) TO authenticated, service_role;
