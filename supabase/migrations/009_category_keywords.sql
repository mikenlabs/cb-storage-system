-- ============================================================
-- CB Storage System for Integrated Computing Business Hub
-- MIGRATION 009 — INTELLIGENT AUTO-CATEGORIZATION BY KEYWORD
-- ============================================================
-- Adds per-category keywords and upgrades auto_assign_category() so
-- files are classified by filename/description BEFORE the MIME-type
-- fallback. Also extends search_files() to match descriptions and
-- keyword entries. Keywords are editable by admins via the UI.

-- ── 1. category_keywords table ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.category_keywords (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id UUID NOT NULL REFERENCES public.file_categories(id) ON DELETE CASCADE,
    keyword TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (category_id, keyword)
);

CREATE INDEX IF NOT EXISTS idx_category_keywords_cat_lower
    ON public.category_keywords (category_id, lower(keyword));

ALTER TABLE public.category_keywords ENABLE ROW LEVEL SECURITY;

-- ── 2. Seed default keywords (admins can edit later) ──────────
WITH seed(cat, kw) AS (VALUES
    ('Documents', 'report'),
    ('Documents', 'thesis'),
    ('Documents', 'assignment'),
    ('Documents', 'proposal'),
    ('Documents', 'resume'),
    ('Documents', 'cv'),
    ('Documents', 'certificate'),
    ('Documents', 'manual'),
    ('Documents', 'policy'),
    ('Documents', 'plan'),
    ('Images', 'photo'),
    ('Images', 'picture'),
    ('Images', 'screenshot'),
    ('Images', 'scan'),
    ('Images', 'image'),
    ('Images', 'signature'),
    ('Software', 'installer'),
    ('Software', 'setup'),
    ('Software', 'driver'),
    ('Software', 'apk'),
    ('Software', 'iso'),
    ('Software', 'firmware'),
    ('Software', 'application'),
    ('Client Files', 'client'),
    ('Client Files', 'customer'),
    ('Client Files', 'account'),
    ('Client Files', 'contract'),
    ('Client Files', 'agreement'),
    ('Client Files', 'order'),
    ('Client Files', 'project'),
    ('Financial Records', 'invoice'),
    ('Financial Records', 'receipt'),
    ('Financial Records', 'payment'),
    ('Financial Records', 'tax'),
    ('Financial Records', 'budget'),
    ('Financial Records', 'expense'),
    ('Financial Records', 'billing'),
    ('Financial Records', 'statement'),
    ('Financial Records', 'financial'),
    ('Financial Records', 'salary'),
    ('Financial Records', 'payroll'),
    ('Communications', 'email'),
    ('Communications', 'memo'),
    ('Communications', 'letter'),
    ('Communications', 'meeting'),
    ('Communications', 'minutes'),
    ('Communications', 'correspondence'),
    ('Communications', 'communication'),
    ('Communications', 'circular'),
    ('Reports', 'report'),
    ('Reports', 'analytics'),
    ('Reports', 'summary'),
    ('Reports', 'dashboard'),
    ('Reports', 'statistics')
)
INSERT INTO public.category_keywords (category_id, keyword)
SELECT fc.id, s.kw
FROM public.file_categories fc
JOIN seed s ON fc.name = s.cat;

-- ── 3. RLS policies ───────────────────────────────────────────
CREATE POLICY "Authenticated users can view category keywords"
    ON public.category_keywords FOR SELECT
    USING (auth.role() = 'authenticated');

CREATE POLICY "Admins can insert category keywords"
    ON public.category_keywords FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

CREATE POLICY "Admins can delete category keywords"
    ON public.category_keywords FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

GRANT SELECT, INSERT, DELETE ON public.category_keywords TO authenticated;
GRANT ALL ON public.category_keywords TO service_role;

-- ── 4. Upgrade auto_assign_category() ─────────────────────────
-- Keyword match first (most hits wins), then MIME-type fallback.
CREATE OR REPLACE FUNCTION public.auto_assign_category()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    haystack TEXT;
    best_cat_id UUID;
    doc_cat_id UUID;
    img_cat_id UUID;
    soft_cat_id UUID;
    arch_cat_id UUID;
BEGIN
    IF NEW.category_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    haystack := lower(coalesce(NEW.name, '') || ' ' || coalesce(NEW.description, ''));

    IF btrim(haystack) <> '' THEN
        SELECT ck.category_id
        INTO best_cat_id
        FROM public.category_keywords ck
        JOIN public.file_categories fc2 ON fc2.id = ck.category_id
        WHERE position(lower(ck.keyword) IN haystack) > 0
        GROUP BY ck.category_id
        ORDER BY count(*) DESC, min(fc2.name) ASC
        LIMIT 1;

        IF best_cat_id IS NOT NULL THEN
            NEW.category_id := best_cat_id;
            RETURN NEW;
        END IF;
    END IF;

    SELECT id INTO doc_cat_id FROM public.file_categories WHERE name = 'Documents' LIMIT 1;
    SELECT id INTO img_cat_id FROM public.file_categories WHERE name = 'Images' LIMIT 1;
    SELECT id INTO soft_cat_id FROM public.file_categories WHERE name = 'Software' LIMIT 1;
    SELECT id INTO arch_cat_id FROM public.file_categories WHERE name = 'Archives' LIMIT 1;

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

-- ── 5. Upgrade search_files() ─────────────────────────────────
-- Now also searches file descriptions and keyword entries.
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
              SELECT 1 FROM public.profiles
              WHERE id = requesting_user AND role = 'admin'
          )
      )
    ORDER BY f.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_files(TEXT, UUID) TO authenticated, service_role;
