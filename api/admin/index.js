import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { persistSession: false, autoRefreshToken: false } }
);

function bearer(req) {
  const value = req.headers.authorization || '';
  return value.startsWith('Bearer ') ? value.slice(7) : '';
}

async function requireAdmin(req) {
  const token = bearer(req);
  if (!token) return { error: 'Sign in required.', status: 401 };

  const { data: authData, error: authError } = await supabase.auth.getUser(token);
  if (authError || !authData?.user) return { error: 'Your session is invalid or expired.', status: 401 };

  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('id, role, approved, suspended')
    .eq('id', authData.user.id)
    .maybeSingle();

  if (profileError) return { error: 'Could not verify administrator access.', status: 500 };
  if (!profile || profile.role !== 'admin' || profile.approved !== true || profile.suspended === true) {
    return { error: 'Administrator access is required.', status: 403 };
  }
  return { user: authData.user };
}

export default async function handler(req, res) {
  if (!['GET', 'POST'].includes(req.method)) {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  const auth = await requireAdmin(req);
  if (auth.error) return res.status(auth.status).json({ error: auth.error });

  if (req.method === 'GET') {
    const [profilesResult, jobsResult, usersResult] = await Promise.all([
      supabase.from('profiles')
        .select('id, display_name, role, approved, suspended, created_at')
        .order('created_at', { ascending: false })
        .limit(100),
      supabase.from('print_jobs')
        .select('id, user_id, file_path, file_name, mime_type, copies, paper_size, color_mode, page_start, page_end, status, message, created_at, updated_at')
        .order('created_at', { ascending: false })
        .limit(100),
      supabase.auth.admin.listUsers({ page: 1, perPage: 100 })
    ]);

    if (profilesResult.error || jobsResult.error || usersResult.error) {
      return res.status(500).json({ error: 'Could not load administrator data.' });
    }

    const emailById = new Map((usersResult.data.users || []).map(u => [u.id, u.email || '']));
    const profiles = (profilesResult.data || []).map(p => ({ ...p, email: emailById.get(p.id) || '' }));
    const jobs = jobsResult.data || [];

    // Create short-lived preview links only for the admin session.
    const jobsWithLinks = await Promise.all(jobs.map(async job => {
      const { data } = await supabase.storage.from('print-files').createSignedUrl(job.file_path, 120);
      return { ...job, preview_url: data?.signedUrl || null, user_email: emailById.get(job.user_id) || '' };
    }));

    return res.status(200).json({ profiles, jobs: jobsWithLinks });
  }

  const { action, id } = req.body || {};
  if (!id || typeof id !== 'string' || id.length > 100) {
    return res.status(400).json({ error: 'A valid record ID is required.' });
  }

  if (action === 'approve_account') {
    const { data, error } = await supabase.from('profiles')
      .update({ approved: true, suspended: false })
      .eq('id', id)
      .select('id')
      .maybeSingle();
    if (error) return res.status(500).json({ error: 'Could not approve this account.' });
    if (!data) return res.status(404).json({ error: 'Account not found.' });
    return res.status(200).json({ ok: true, message: 'Account approved.' });
  }

  if (action === 'suspend_account') {
    if (id === auth.user.id) return res.status(400).json({ error: 'You cannot suspend your own administrator account.' });
    const { data, error } = await supabase.from('profiles')
      .update({ suspended: true, approved: false })
      .eq('id', id)
      .neq('role', 'admin')
      .select('id')
      .maybeSingle();
    if (error) return res.status(500).json({ error: 'Could not suspend this account.' });
    if (!data) return res.status(404).json({ error: 'Account not found or cannot be suspended.' });
    return res.status(200).json({ ok: true, message: 'Account access suspended.' });
  }

  if (action === 'approve_job' || action === 'reject_job') {
    const status = action === 'approve_job' ? 'approved' : 'rejected';
    const { data, error } = await supabase.from('print_jobs')
      .update({
        status,
        message: action === 'approve_job' ? 'Approved by administrator; waiting for the printer agent.' : 'Rejected by administrator.',
        updated_at: new Date().toISOString()
      })
      .eq('id', id)
      .eq('status', 'queued')
      .select('id')
      .maybeSingle();
    if (error) return res.status(500).json({ error: 'Could not update this print request.' });
    if (!data) return res.status(409).json({ error: 'This request is no longer awaiting review.' });
    return res.status(200).json({ ok: true, message: `Print request ${status}.` });
  }

  return res.status(400).json({ error: 'Unknown administrator action.' });
}
