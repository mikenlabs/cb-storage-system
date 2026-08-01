-- Migration 002: Storage Bucket Setup and RLS Policies
-- CB Storage System for Integrated Computing Business Hub

-- ============================================================
-- STORAGE BUCKET
-- ============================================================
INSERT INTO storage.buckets (id, name, public, avif_autodetection, file_size_limit, allowed_mime_types)
VALUES (
    'hub-storage',
    'hub-storage',
    FALSE,
    FALSE,
    52428800, -- 50 MB
    ARRAY[
        'application/pdf',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'image/jpeg',
        'image/png',
        'image/gif',
        'image/webp',
        'text/plain',
        'text/csv',
        'application/zip',
        'application/x-rar-compressed',
        'application/x-7z-compressed'
    ]
) ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- TABLE RLS POLICIES
-- ============================================================

-- Profiles: users can read own profile, admins read all
CREATE POLICY "Users can view own profile"
    ON profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Admins can view all profiles"
    ON profiles FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- File Categories: all authenticated users can read
CREATE POLICY "Authenticated users can view categories"
    ON file_categories FOR SELECT
    USING (auth.role() = 'authenticated');

CREATE POLICY "Only admins can manage categories"
    ON file_categories FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

CREATE POLICY "Only admins can update categories"
    ON file_categories FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

CREATE POLICY "Only admins can delete categories"
    ON file_categories FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- Files: users can read own files, admins read all
CREATE POLICY "Users can view own files"
    ON files FOR SELECT
    USING (uploaded_by = auth.uid() AND deleted_at IS NULL);

CREATE POLICY "Admins can view all files"
    ON files FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
        AND deleted_at IS NULL
    );

CREATE POLICY "Users can insert own files"
    ON files FOR INSERT
    WITH CHECK (uploaded_by = auth.uid());

CREATE POLICY "Users can update own files"
    ON files FOR UPDATE
    USING (uploaded_by = auth.uid())
    WITH CHECK (uploaded_by = auth.uid());

CREATE POLICY "Admins can update any file"
    ON files FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- Soft delete: users can soft-delete own files
CREATE POLICY "Users can soft delete own files"
    ON files FOR UPDATE
    USING (uploaded_by = auth.uid())
    WITH CHECK (deleted_at IS NOT NULL);

-- Backup Logs: admins only
CREATE POLICY "Admins can view backup logs"
    ON backup_logs FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

CREATE POLICY "Admins can insert backup logs"
    ON backup_logs FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

CREATE POLICY "Admins can update backup logs"
    ON backup_logs FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- Recovery Logs: admins only
CREATE POLICY "Admins can view recovery logs"
    ON recovery_logs FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

CREATE POLICY "Admins can insert recovery logs"
    ON recovery_logs FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

CREATE POLICY "Admins can update recovery logs"
    ON recovery_logs FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- Audit Logs: admins can read, system inserts via trigger
CREATE POLICY "Admins can view audit logs"
    ON audit_logs FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

CREATE POLICY "Authenticated users can insert audit logs"
    ON audit_logs FOR INSERT
    WITH CHECK (auth.role() = 'authenticated');

-- ============================================================
-- STORAGE RLS POLICIES
-- ============================================================
CREATE POLICY "Authenticated users can read own files"
    ON storage.objects FOR SELECT
    USING (
        bucket_id = 'hub-storage'
        AND auth.role() = 'authenticated'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY "Admins can read all storage files"
    ON storage.objects FOR SELECT
    USING (
        bucket_id = 'hub-storage'
        AND EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

CREATE POLICY "Authenticated users can upload own files"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'hub-storage'
        AND auth.role() = 'authenticated'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY "Users can update own storage files"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'hub-storage'
        AND auth.role() = 'authenticated'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY "Users can delete own storage files"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'hub-storage'
        AND auth.role() = 'authenticated'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY "Admins can delete any storage file"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'hub-storage'
        AND EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );
