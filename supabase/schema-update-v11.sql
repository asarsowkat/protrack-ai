-- ProTrack schema update v11 (ProTrackAI v3.2): quantity beyond the scope in daily reports.
-- A daily report may record more than the activity's remaining scope quantity. When it does, the site engineer
-- (or whoever reviews it) must justify the variation for each such activity while reviewing; the justification is kept
-- with the report and cannot be changed. The approver cannot approve a quantity that was not justified.
-- Additive: one new table and one helper; dpr_act gains an optional last argument (p_just). Safe to run twice.
-- Undo with schema-rollback-v11.sql (keeps every justification).

create table if not exists dpr_qty_just (
  id bigserial primary key,
  dpr_id text not null references dprs(id) on delete cascade,
  activity_id text not null,
  qty numeric not null,            -- this report's quantity for the activity when it was justified
  cum_qty numeric not null,        -- executed to date including this report
  scope_qty numeric not null,      -- the activity's total quantity
  note text not null check (length(btrim(note)) >= 10),
  by_user uuid references profiles(id), by_name text,
  at_time timestamptz not null default now());
create index if not exists dpr_qty_just_dpr on dpr_qty_just (dpr_id, activity_id);
alter table dpr_qty_just enable row level security;
drop policy if exists dqj_read on dpr_qty_just;
create policy dqj_read on dpr_qty_just for select using (exists (select 1 from dprs d where d.id = dpr_id and can_see(d.project_id)));
drop trigger if exists trg_dqj_append on dpr_qty_just;
create trigger trg_dqj_append before update or delete on dpr_qty_just for each row execute function pt_append_only();
drop trigger if exists trg_dqj_truncate on dpr_qty_just;
create trigger trg_dqj_truncate before truncate on dpr_qty_just execute function pt_no_truncate();
-- no write policies: only dpr_act writes justifications

-- activities on a report whose quantity to date goes beyond the scope: prior quantity + every submitted, reviewed or
-- approved report up to the same date (other reports) + this report
create or replace function pt_dpr_over(p_id text) returns table (activity_id text, qty numeric, cum_qty numeric, scope_qty numeric)
language sql stable security definer set search_path = public as $$
  select * from (
    select m.activity_id, m.q,
           coalesce(a.prior_qty, 0) + m.q + coalesce((
             select sum(coalesce(l2.qty, 0)) from dpr_lines l2 join dprs d2 on d2.id = l2.dpr_id
              where d2.project_id = d.project_id and l2.activity_id = m.activity_id and d2.id <> d.id
                and d2.status in ('Submitted','Reviewed','Approved') and d2.report_date <= d.report_date), 0) as cum,
           a.qty as scope
      from dprs d
      join (select l.activity_id, sum(coalesce(l.qty, 0)) q from dpr_lines l where l.dpr_id = p_id group by l.activity_id) m on true
      join activities a on a.project_id = d.project_id and a.id = m.activity_id
     where d.id = p_id) x
   where coalesce(x.scope, 0) > 0 and x.cum > x.scope + 0.000001 $$;
revoke execute on function pt_dpr_over(text) from public, anon, authenticated;

drop function if exists dpr_act(text, text, text, int);
create or replace function dpr_act(p_id text, p_action text, p_note text default null, p_secs int default 0, p_just jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); r text := role_of(auth.uid()); d dprs; rev uuid; reviewed_by uuid; apr uuid;
  boss boolean; can boolean := false; kind text; o record; jt text; miss text;
begin
  if me is null or r is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select * into d from dprs where id = p_id for update;
  if d.id is null or not user_sees(me, d.project_id) then raise exception 'Report not found' using errcode = '42501'; end if;
  if p_action in ('return','reject') and coalesce(trim(p_note), '') = '' then
    raise exception 'A comment is required to % a report', p_action; end if;

  boss := r in ('pm','sa');
  rev := dpr_reviewer(d.project_id, d.foreman_id);
  select a.by_user into reviewed_by from dpr_audit a where a.dpr_id = d.id and a.action = 'Reviewed' order by a.seq desc limit 1;
  -- approver: the site manager assigned to the engineer who reviewed it, else to the assigned engineer
  apr := dpr_approver(d.project_id, coalesce(case when role_of(reviewed_by) = 'eng' then reviewed_by end, rev));

  if d.status = 'Submitted' then
    kind := 'review';
    can := case p_action
      when 'review' then boss or (r = 'eng' and rev = me) or (r = 'pm' and rev is null)
      when 'return' then boss or (r = 'eng' and rev = me)
      when 'reject' then boss
      else false end;
  elsif d.status = 'Reviewed' then
    kind := 'approve';
    can := case p_action
      when 'approve' then boss or (r = 'sm' and apr = me)
      when 'return'  then boss or (r = 'sm' and apr = me)
      when 'reject'  then boss or (r = 'sm' and apr = me)
      else false end;
  else
    raise exception 'This report is % and cannot be acted on', lower(d.status::text) using errcode = '42501';
  end if;
  -- an unassigned step compares with null; treat "unknown" as "no"
  if not coalesce(can, false) then raise exception 'You are not the reviewer or approver assigned to this report' using errcode = '42501'; end if;

  perform pt_begin();
  -- v11: a quantity beyond the activity's scope is accepted, but the reviewer must justify it, and the approver
  -- cannot approve a quantity that was not justified (for example one raised by an edit after review)
  if p_action = 'review' then
    if p_just is not null and jsonb_typeof(p_just) <> 'object' then raise exception 'Justifications must be given per activity'; end if;
    select string_agg(x.activity_id, ', ' order by x.activity_id) into miss from pt_dpr_over(d.id) x
     where length(btrim(coalesce(p_just ->> x.activity_id, ''))) < 10;
    if miss is not null then
      raise exception 'Justify the quantity variation (at least a few words) for the activities beyond their scope quantity: %', miss; end if;
    for o in select * from pt_dpr_over(d.id) loop
      jt := left(btrim(p_just ->> o.activity_id), 1000);
      insert into dpr_qty_just (dpr_id, activity_id, qty, cum_qty, scope_qty, note, by_user, by_name)
      values (d.id, o.activity_id, o.qty, o.cum_qty, o.scope_qty, jt, me, name_of(me));
      perform pt_audit(d.id, 'Quantity variation justified', o.activity_id || ': ' || jt);
    end loop;
  elsif p_action = 'approve' then
    select string_agg(x.activity_id, ', ' order by x.activity_id) into miss from pt_dpr_over(d.id) x
     where not exists (select 1 from dpr_qty_just j where j.dpr_id = d.id and j.activity_id = x.activity_id and j.qty = x.qty);
    if miss is not null then
      raise exception 'The quantity beyond the scope of % has not been justified by the reviewer; return the report so the site engineer can justify it', miss; end if;
  end if;
  update dprs set
    status = case p_action when 'review' then 'Reviewed' when 'approve' then 'Approved'
                           when 'return' then 'Draft' else 'Rejected' end::dpr_status,
    returned = (p_action = 'return'), updated_at = now(),
    timing = pt_timing(timing, kind, p_secs)
   where id = d.id returning * into d;
  perform pt_audit(d.id, case p_action when 'review' then 'Reviewed' when 'approve' then 'Approved'
                                       when 'return' then 'Returned' else 'Rejected' end, p_note);
  return jsonb_build_object('id', d.id, 'status', d.status, 'timing', d.timing);
end $$;

revoke execute on function dpr_act(text, text, text, int, jsonb) from public, anon, authenticated;
grant execute on function dpr_act(text, text, text, int, jsonb) to authenticated;
