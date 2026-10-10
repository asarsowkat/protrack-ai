# ProTrack Supabase updates (current: v3.1)

| File | Run it? |
|---|---|
| `schema-update-v4.sql` | **Yes, on your live project** (after v2 and v3 are in). Step 1 of STAGE-2B-SETUP.md |
| `schema-update-v5.sql` | **Yes, on your live project, after v4.** Step 1 of STAGE-3-SETUP.md |
| `schema-update-v6.sql` | **Yes, on your live project, after v5.** Step 1 of STAGE-4-SETUP.md |
| `schema-update-v7.sql` | **Yes, on your live project, after v6.** Step 1 of STAGE-4B-SETUP.md |
| `schema-update-v8.sql` | **Yes, on your live project, after v7.** Step 1 of STAGE-5-SETUP.md |
| `schema-update-v9.sql` | **Yes, on your live project, after v8.** Step 1 of STAGE-6-SETUP.md |
| `schema-update-v10.sql` | **Yes, on your live project, after v9.** Step 1 of STAGE-7-SETUP.md |
| `schema-rollback-v10.sql` | Only to undo v10. Keeps all data |
| `schema-rollback-v9.sql` | Only to undo v9. Keeps all data |
| `schema-rollback-v8.sql` | Only to undo v8. Keeps all data |
| `schema-rollback-v7.sql` | Only to undo v7. Keeps all data |
| `schema-rollback-v6.sql` | Only to undo v6. Keeps all data |
| `schema-rollback-v5.sql` | Only to undo v5. Keeps all data |
| `schema-rollback-v4.sql` | Only to undo v4. Keeps all data |
| `schema.sql`, `schema-update-v2.sql`, `schema-update-v3.sql` | Only on a **new, empty** project (staging, see STAGING.md). Your live project already has them |
| `tests/` | **Never on Supabase.** Test tools for a local PostgreSQL |
