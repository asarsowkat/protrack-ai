# ProTrack Supabase update for v2.5

| File | Run it? |
|---|---|
| `schema-update-v4.sql` | **Yes, on your live project** (after v2 and v3 are in). Step 1 of STAGE-2B-SETUP.md |
| `schema-rollback-v4.sql` | Only to undo v4. Keeps all data |
| `schema.sql`, `schema-update-v2.sql`, `schema-update-v3.sql` | Only on a **new, empty** project (staging, see STAGING.md). Your live project already has them |
| `tests/` | **Never on Supabase.** Test tools for a local PostgreSQL |
