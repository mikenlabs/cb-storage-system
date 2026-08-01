-- ============================================================
-- 005: GRANT table permissions to authenticated role
-- RLS policies exist but role-level GRANTs were missing,
-- causing "permission denied for table" errors.
-- ============================================================

-- Profiles
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;

-- File Categories
GRANT SELECT, INSERT, UPDATE, DELETE ON public.file_categories TO authenticated;

-- Files
GRANT SELECT, INSERT, UPDATE, DELETE ON public.files TO authenticated;

-- Backup logs
GRANT SELECT, INSERT ON public.backup_logs TO authenticated;

-- Recovery logs
GRANT SELECT, INSERT ON public.recovery_logs TO authenticated;

-- Audit logs
GRANT SELECT ON public.audit_logs TO authenticated;
