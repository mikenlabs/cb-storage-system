-- ============================================================
-- CB Storage System for Integrated Computing Business Hub
-- MIGRATION 010 — KEYWORDS FOR ARCHIVES + EXCEL CATEGORIES
-- ============================================================
-- Archives had no keywords (MIME fallback covered zip/rar/7z) and the
-- user-created "excel" category had none either, so Excel files never
-- auto-categorised into it. Adds keyword sets for both.

INSERT INTO public.category_keywords (category_id, keyword)
SELECT fc.id, s.kw
FROM public.file_categories fc
JOIN (VALUES
    ('Archives', 'archive'),
    ('Archives', 'archives'),
    ('Archives', 'zip'),
    ('Archives', 'rar'),
    ('Archives', '7z'),
    ('Archives', 'tar'),
    ('Archives', 'gz'),
    ('Archives', 'backup'),
    ('Archives', 'compressed'),
    ('Archives', 'bundle'),
    ('Archives', 'extract'),
    ('excel', 'excel'),
    ('excel', 'spreadsheet'),
    ('excel', 'xls'),
    ('excel', 'xlsx'),
    ('excel', 'csv'),
    ('excel', 'workbook'),
    ('excel', 'sheet'),
    ('excel', 'pivot'),
    ('excel', 'data'),
    ('excel', 'dataset')
) AS s(cat, kw) ON fc.name = s.cat
ON CONFLICT (category_id, keyword) DO NOTHING;
