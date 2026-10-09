# A staging copy of ProTrack (try changes before your team sees them)

A staging copy is a second, separate ProTrack with its own server and its own website. You test a new version there first; your live site and live data are never touched. Both can run on Supabase's and GitHub's free plans.

## One-time setup (about 40 minutes)

### 1. A second Supabase project
1. supabase.com → **New project**. Name it `protrack-staging`, region **Mumbai** (same as live), choose a database password and keep it.
2. When it is ready: **SQL Editor → New query**, and run these files from the Supabase update package, one at a time, in this order:
   `schema.sql`, `schema-update-v2.sql`, `schema-update-v3.sql`, `schema-update-v4.sql`.
3. **Authentication → Users → Add user**: create your own test account (tick Auto Confirm). Then in SQL Editor:
   ```sql
   insert into profiles (id, name, role)
   select id, 'Staging Admin', 'sa' from auth.users where email = 'YOUR-TEST-EMAIL';
   ```
4. **Project Settings → API**: copy the **Project URL** and the **anon public** key.

### 2. A second website
1. github.com → **New repository** → name `protrack-staging`, **Public**, tick "Add a README".
2. Upload `index.html` and `guide.html`.
3. Create `config.js` in that repository (Add file → Create new file) with the **staging** values:
   ```js
   window.PROTRACK = {
     SUPABASE_URL: 'https://YOUR-STAGING-REF.supabase.co',
     SUPABASE_ANON_KEY: 'the staging anon public key',
     SITE_URL: 'https://asarsowkat.github.io/protrack-staging/'
   };
   ```
4. **Settings → Pages → Branch: main → Save**. After two minutes the staging site is at `https://asarsowkat.github.io/protrack-staging/`.

Never copy the live key into staging or the staging key into live. Each site's `config.js` points to its own server.

## Each new version
1. Run the new `schema-update-*.sql` on **staging** first; upload the new `index.html` to **protrack-staging**.
2. Follow the version's test steps on staging, with test accounts and test projects.
3. Only when staging is fine: repeat on live, at a quiet time, after downloading a server backup (Settings → System).

## Test data
Use made-up projects and people on staging. Do not copy live reports into staging: staging is for trying things, and anyone you give a staging account could see what is there.
