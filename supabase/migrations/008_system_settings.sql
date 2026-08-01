-- Migration 008: System settings (persisted backup schedule)
-- CB Storage System for Integrated Computing Business Hub

-- ============================================================
-- SYSTEM SETTINGS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.system_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;

-- Readable by any authenticated user (contains no sensitive data);
-- writes are restricted to the service_role (bypasses RLS).
DROP POLICY IF EXISTS "settings_readable_by_authenticated" ON public.system_settings;
CREATE POLICY "settings_readable_by_authenticated"
    ON public.system_settings
    FOR SELECT
    USING (auth.role() = 'authenticated');

-- ============================================================
-- GRANTS
-- ============================================================
GRANT SELECT ON public.system_settings TO authenticated;
GRANT ALL ON public.system_settings TO service_role;
