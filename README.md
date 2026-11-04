# Networking Remote — first-stage scaffold

This is a separate remote project. It does not replace or modify the existing XAMPP `Networking` folder or its MySQL database.

## Included
- `public/index.html`: remote account, approval status, upload form, and personal job history.
- `public/config.js`: browser-safe Supabase URL and publishable key placeholders.
- `supabase/migration_remote.sql`: additive migration for print settings and approved-user upload restrictions.
- `api/agent/next.js` and `api/agent/result.js`: protected Windows-agent endpoints.
- `agent/print-agent.ps1`: Windows polling agent using outbound HTTPS.
- `agent/print-jpg.ps1`: JPG print helper from the tested local package.

## Important limitations in this first scaffold
- Admin approval is performed in Supabase Table Editor for now; an admin dashboard is a later step.
- Do not deploy until environment variables and the migration are configured.
- A successful Windows queue submission is not proof that paper physically exited the printer.
- The PDF range option is passed to SumatraPDF; actual PDF page count validation is still required before production.
- Configure Supabase Auth redirect URLs for the final Vercel domain before testing email confirmation.

## Supabase migration
Run `supabase/migration_remote.sql` in the existing Supabase SQL Editor AFTER the initial schema. It is additive and does not drop existing tables.

## Vercel environment variables
Set these in Project Settings → Environment Variables:
- `SUPABASE_URL` — project URL
- `SUPABASE_SERVICE_ROLE_KEY` — secret; server-side only
- `AGENT_TOKEN` — a long random secret shared only with the Windows agent

Never put the service-role key or agent token in `public/config.js`, GitHub, or chat.

## Browser configuration
Edit `public/config.js` with the Supabase Project URL and Publishable key. The publishable key is public by design; database access is controlled by RLS.

## Agent setup
1. Copy `agent/config.example.json` to `agent/config.json`.
2. Set the deployed HTTPS Vercel URL, matching agent token, exact printer queue name, and SumatraPDF path.
3. Keep `config.json` private; it is gitignored.
4. Run PowerShell: `.\print-agent.ps1`.
5. Keep the Windows laptop on, connected to the Brother printer, and the agent running.

## Deployment is not ready yet
The agent endpoints and UI are a development scaffold. Before live use, add an admin approval interface, race-safe job claiming, stricter PDF validation/page-count enforcement, job retry handling, and end-to-end testing.
