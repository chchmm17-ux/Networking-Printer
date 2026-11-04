-- 1. Keep the existing print options.
ALTER TABLE public.print_jobs
  ADD COLUMN IF NOT EXISTS paper_size TEXT NOT NULL DEFAULT 'A4'
    CHECK (paper_size IN ('A4','A5','A3','LETTER','LEGAL','B5')),
  ADD COLUMN IF NOT EXISTS color_mode TEXT NOT NULL DEFAULT 'color'
    CHECK (color_mode IN ('color','bw')),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();


-- 2. Remove the old account-approval requirement.
DROP POLICY IF EXISTS "Users can submit own jobs"
ON public.print_jobs;

DROP POLICY IF EXISTS "Approved users can submit own jobs"
ON public.print_jobs;


-- 3. Allow signed-in, non-suspended users to submit print requests.
CREATE POLICY "Users can submit own jobs"
ON public.print_jobs
FOR INSERT
TO authenticated
WITH CHECK (
  user_id = (SELECT auth.uid())
  AND status = 'queued'
  AND EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND COALESCE(p.suspended, FALSE) = FALSE
  )
);


-- 4. Remove the old account-approval requirement for uploads.
DROP POLICY IF EXISTS "Users can upload to own folder"
ON storage.objects;

DROP POLICY IF EXISTS "Approved users can upload to own folder"
ON storage.objects;


-- 5. Allow signed-in, non-suspended users to upload to their own folder.
CREATE POLICY "Users can upload to own folder"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'print-files'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
  AND EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND COALESCE(p.suspended, FALSE) = FALSE
  )
);


-- 6. Keep the storage bucket private.
UPDATE storage.buckets
SET public = FALSE,
    file_size_limit = 26214400,
    allowed_mime_types = ARRAY['application/pdf','image/jpeg']
WHERE id = 'print-files';
