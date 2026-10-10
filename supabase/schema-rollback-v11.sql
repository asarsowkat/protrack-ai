-- ProTrack: undo schema update v11 (ProTrackAI v3.2). Puts back the v4 review and approval function (no justification
-- needed for quantities beyond the scope). Keeps every justification already recorded. Safe to run twice.
drop function if exists dpr_act(text, text, text, int, jsonb);
drop function if exists pt_dpr_over(text);
create or replace function dpr_act(p_id text, p_action text, p_note text default null, p_secs int default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); r text := role_of(auth.uid()); d dprs; rev uuid; reviewed_by uuid; apr uuid;
  boss boolean; can boolean := false; kind text;
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

revoke execute on function dpr_act(text, text, text, int) from public, anon, authenticated;
grant execute on function dpr_act(text, text, text, int) to authenticated;
