-- ProTrack schema update v44 (ProTrackAI v3.40): delete an uploaded tender costing file in Budget & Cost Management.
-- 1. bcm_file_delete(p): Tender File Intake → Delete. The person who uploaded the file (with bcm.upload) or a reviewer
--    (bcm.review) deletes it, with a reason of 3 characters or more. Refused while the batch is withdrawn (its files are kept
--    with it), while the file is being read, and while a budget version prepared from the batch is not rejected or cancelled.
--    When people have decided lines of the file, the call needs confirm = true.
--    What goes: the file's record and every line read from it (all runs), with their classification, splits and sheet roles
--    (by cascade; the lines' freeze lets them go once their file is gone). The duplicate groups that used its lines become
--    Obsolete. What stays: the classification history (bcm_class_hist) and the audit log, which gets "File deleted" with the
--    name, SHA-256, size, batch, runs, lines, decided lines and the reason. The same file can then be uploaded again.
-- 2. The stored workbook: the app removes it from the private bucket bcm-tender after the call. The bucket lets a person
--    remove a workbook only when no file record points to it any more, and only on a project where they upload or review.
-- 3. bcm_features() says version 44 and "file_delete": true; the app shows Delete only then.
-- Needs schema-update-v42.sql (STAGE-36-SETUP). Additive. Safe to run twice. Undo: schema-rollback-v44.sql.

do $$ begin
  if to_regclass('public.bcm_versions') is null or to_regclass('public.bcm_sap_reports') is null then
    raise exception 'Run schema-update-v41.sql (STAGE-35-SETUP) and v42 (STAGE-36-SETUP) first, then this update'; end if;
end $$;

-- ------------------------------------------------------------------ 1. the deletion
create or replace function bcm_file_delete(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; who text; rl text; f bcm_files; b bcm_batches; vs text; ids text[]; n int; dec int; why text := trim(coalesce(p ->> 'reason', ''));
begin
  select * into u, who, rl from pt_bcm_me();
  select * into f from bcm_files where id = p ->> 'file_id' for update;
  if f.id is null then raise exception 'Unknown file'; end if;
  select * into b from bcm_batches where id = f.batch_id for update;
  if b.id is null or b.status <> 'Open' then raise exception 'The batch is withdrawn: its files are kept with it'; end if;
  if not (pt_bcm(u, f.project_id, 'bcm.review') or (f.created_by = u and pt_bcm(u, f.project_id, 'bcm.upload'))) then
    raise exception 'Only the person who uploaded the file, or a reviewer, deletes it' using errcode = '42501'; end if;
  if f.status = 'Extracting' then raise exception 'The file is being read; wait until it finishes'; end if;
  select string_agg(v.kind || ' rev ' || v.rev_no || ' (' || v.status || ')', ', ' order by v.prepared_at) into vs
    from bcm_versions v where v.batch_id = b.id and v.status not in ('Rejected','Cancelled');
  if vs is not null then raise exception 'Budget version % was prepared from this batch. Reject or cancel it first; the file stays.', vs; end if;
  if length(why) < 3 then raise exception 'Give the reason'; end if;
  select coalesce(array_agg(l.id), '{}'::text[]) into ids from bcm_lines l where l.file_id = f.id;
  n := coalesce(array_length(ids, 1), 0);
  select count(*) into dec from bcm_class c where c.line_id = any(ids) and c.status in ('Confirmed','Rejected','Excluded with Reason');
  if dec > 0 and not coalesce((p ->> 'confirm')::boolean, false) then
    raise exception 'People have decided % line% of this file. Deleting it removes those decisions too (their history is kept). Confirm to go on.', dec, case when dec = 1 then '' else 's' end; end if;
  update bcm_dups d set status = 'Obsolete', updated_at = now()
    where d.batch_id = b.id and d.status <> 'Obsolete'
      and exists (select 1 from jsonb_array_elements_text(coalesce(d.lines, '[]'::jsonb) || coalesce(d.backup_lines, '[]'::jsonb)) x where x = any(ids));
  -- the file's record; its lines (bcm_lines), their classification (bcm_class) and splits (bcm_alloc), and its sheet roles
  -- (bcm_roles) follow by cascade
  delete from bcm_files where id = f.id;
  perform pt_bcm_log(u, who, rl, 'File deleted', 'file', f.id, f.project_id, jsonb_build_object('name', f.name, 'sha256', f.sha256, 'size', f.size,
    'batch', b.id, 'runs', f.run, 'lines', n, 'decided', dec, 'reason', why));
  return jsonb_build_object('ok', true, 'id', f.id, 'lines', n, 'decided', dec, 'path', f.path);
end $$;
revoke execute on function bcm_file_delete(jsonb) from public, anon;
grant execute on function bcm_file_delete(jsonb) to authenticated;

-- ------------------------------------------------------------------ 2. removing the stored workbook
-- path: bcm/<project>/<batch>/<sha256>.<xlsx|xls|xlsm>; only a workbook no file record points to, on a project where the
-- person uploads or reviews
create or replace function pt_bcm_file_gone(u uuid, path text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(split_part(path, '/', 1) = 'bcm'
    and (pt_bcm(u, split_part(path, '/', 2), 'bcm.upload') or pt_bcm(u, split_part(path, '/', 2), 'bcm.review'))
    and not exists (select 1 from bcm_files f where f.path = pt_bcm_file_gone.path), false) $$;
revoke execute on function pt_bcm_file_gone(uuid, text) from public, anon;
grant execute on function pt_bcm_file_gone(uuid, text) to authenticated;
drop policy if exists protrack_bcm_del on storage.objects;
create policy protrack_bcm_del on storage.objects for delete to authenticated
  using (bucket_id = 'bcm-tender' and public.pt_bcm_file_gone(auth.uid(), name));

-- ------------------------------------------------------------------ 3. the version the app reads
create or replace function bcm_features() returns jsonb language sql stable as $$ select '{"version": 44, "stages": [1, 2, 3, 4], "sap_wbs": true, "file_delete": true}'::jsonb $$;
grant execute on function bcm_features() to authenticated;
