-- Grant service_role full access to all tables
-- (needed because service_supabase client uses service_role PG role)
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
