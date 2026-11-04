-- Run AFTER the initial schema you already executed.
-- Adds remote print options and tightens account-approval access.
ALTER TABLE public.print_jobs
  ADD COLUMN IF NOT EXISTS paper_size TEXT NOT NULL DEFAULT 'A4'
    CHECK (paper_size IN ('A4','A5','A3','LETTER','LEGAL','B5')),
  ADD COLUMN IF NOT EXISTS color_mode TEXT NOT NULL DEFAULT 'color'
    CHECK (color_mode IN ('color','bw')),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- A user must be email-confirmed by Supabase AND approved by an admin
-- before creating print requests or uploading files.
DROP POLICY IF EXISTS "Users can submit own jobs" ON public.print_jobs;
CREATE POLICY "Approved users can submit own jobs"
ON public.print_jobs FOR INSERT TO authenticated
WITH CHECK (
  user_id = (SELECT auth.uid())
  AND status = 'queued'
  AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = (SELECT auth.uid()) AND p.approved = TRUE
  )
);

DROP POLICY IF EXISTS "Users can upload to own folder" ON storage.objects;
CREATE POLICY "Approved users can upload to own folder"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'print-files'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
  AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = (SELECT auth.uid()) AND p.approved = TRUE
  )
);

-- Keep the bucket private. Do not create public read access.
UPDATE storage.buckets
SET public = FALSE,
    file_size_limit = 26214400,
    allowed_mime_types = ARRAY['application/pdf','image/jpeg']
WHERE id = 'print-files';
