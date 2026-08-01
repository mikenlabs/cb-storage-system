-- Migration 001: Initial Schema
-- CB Storage System for Integrated Computing Business Hub

-- ============================================================
-- EXTENSIONS
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================================
-- 1. PROFILES TABLE (extends Supabase Auth)
-- ============================================================
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'staff' CHECK (role IN ('admin', 'staff')),
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Auto-create profile on user signup
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

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();

-- ============================================================
-- 2. FILE CATEGORIES TABLE
-- ============================================================
CREATE TABLE file_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    color TEXT DEFAULT '#6366f1',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE file_categories ENABLE ROW LEVEL SECURITY;

-- Seed default categories
INSERT INTO file_categories (name, description, color) VALUES
    ('Documents', 'Office documents, PDFs, text files', '#3b82f6'),
    ('Images', 'Image files and graphics', '#10b981'),
    ('Software', 'Software installers and executables', '#f59e0b'),
    ('Client Files', 'Client-specific documents and records', '#8b5cf6'),
    ('Financial Records', 'Invoices, receipts, financial statements', '#ef4444'),
    ('Communications', 'Emails, correspondence, memos', '#06b6d4'),
    ('Reports', 'Activity reports and analytics', '#ec4899'),
    ('Archives', 'Compressed and archived files', '#6b7280');

-- ============================================================
-- 3. FILES TABLE (metadata for intelligent file management)
-- ============================================================
CREATE TABLE files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    type TEXT NOT NULL DEFAULT 'application/octet-stream',
    category_id UUID REFERENCES file_categories(id) ON DELETE SET NULL,
    size BIGINT NOT NULL DEFAULT 0,
    storage_path TEXT NOT NULL,
    uploaded_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    description TEXT,
    checksum TEXT,
    is_duplicate BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- Indexes for efficient search and retrieval
CREATE INDEX idx_files_name ON files USING gin(name gin_trgm_ops);
CREATE INDEX idx_files_type ON files(type);
CREATE INDEX idx_files_category ON files(category_id);
CREATE INDEX idx_files_uploaded_by ON files(uploaded_by);
CREATE INDEX idx_files_created_at ON files(created_at DESC);
CREATE INDEX idx_files_checksum ON files(checksum);
CREATE INDEX idx_files_deleted_at ON files(deleted_at);

ALTER TABLE files ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 4. BACKUP LOGS TABLE
-- ============================================================
CREATE TABLE backup_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type TEXT NOT NULL CHECK (type IN ('scheduled', 'manual')),
    status TEXT NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'completed', 'failed')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    file_count INTEGER DEFAULT 0,
    size_bytes BIGINT DEFAULT 0,
    error_message TEXT,
    triggered_by UUID REFERENCES profiles(id) ON DELETE SET NULL
);

ALTER TABLE backup_logs ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 5. RECOVERY LOGS TABLE
-- ============================================================
CREATE TABLE recovery_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    backup_log_id UUID REFERENCES backup_logs(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'restoring' CHECK (status IN ('restoring', 'completed', 'failed')),
    requested_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    error_message TEXT
);

ALTER TABLE recovery_logs ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 6. AUDIT LOGS TABLE
-- ============================================================
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    action TEXT NOT NULL CHECK (action IN ('upload', 'download', 'delete', 'restore', 'backup', 'recover', 'login', 'update')),
    resource_type TEXT NOT NULL CHECK (resource_type IN ('file', 'backup', 'recovery', 'user', 'category')),
    resource_id UUID,
    details JSONB,
    ip_address INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);

ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- AUTO-UPDATE UPDATED_AT TRIGGER
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER set_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER set_files_updated_at
    BEFORE UPDATE ON files
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();
