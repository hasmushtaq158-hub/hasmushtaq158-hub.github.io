begin;

-- The daily code remains an internal compatibility value for older clients.
-- Current workers are authorized by their authenticated account and assignment.

create or replace function public.worker_open_attractions_auto()
returns table(day_id bigint, attraction_id bigint, attraction_name text, price numeric)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_day_id bigint;
begin
  if not exists (
    select 1 from public.profiles
    where id=auth.uid() and role='worker' and active
  ) then raise exception 'WORKER_ONLY'; end if;

  select id into v_day_id
  from public.business_days
  where status='OPEN'
  order by id desc limit 1;

  if v_day_id is null then return; end if;

  return query
  select ad.day_id,ad.attraction_id,a.name,a.price::numeric
  from public.attraction_days ad
  join public.attractions a on a.id=ad.attraction_id
  where ad.day_id=v_day_id and ad.is_open and a.active
  order by ad.attraction_id;
end;
$function$;

create or replace function public.begin_shift_auto(p_attraction_id bigint)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_code text;
begin
  select daily_code into v_code
  from public.business_days
  where status='OPEN'
  order by id desc limit 1;
  if v_code is null then raise exception 'NO_OPEN_DAY'; end if;
  perform public.begin_shift(p_attraction_id,v_code);
end;
$function$;

create or replace function public.worker_request_replacement_auto(p_attraction_id bigint)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_code text;
begin
  select daily_code into v_code
  from public.business_days
  where status='OPEN'
  order by id desc limit 1;
  if v_code is null then raise exception 'NO_OPEN_DAY'; end if;
  return public.worker_request_replacement(p_attraction_id,v_code);
end;
$function$;

create or replace function public.worker_replacement_queue_auto()
returns table(
  day_id bigint,is_daily_replacement boolean,request_id bigint,request_role text,request_status text,
  queue_position integer,attraction_id bigint,attraction_name text,other_worker_name text,
  requested_at timestamptz,accepted_at timestamptz,due_at timestamptz,seconds_remaining integer,overdue boolean
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_day_id bigint; v_is_replacement boolean;
begin
  if not exists (
    select 1 from public.profiles
    where id=auth.uid() and role='worker' and active
  ) then raise exception 'WORKER_ONLY'; end if;

  select id into v_day_id
  from public.business_days
  where status='OPEN'
  order by id desc limit 1;
  if v_day_id is null then raise exception 'NO_OPEN_DAY'; end if;

  select exists(
    select 1 from public.day_replacement_workers drw
    where drw.day_id=v_day_id and drw.worker_id=auth.uid() and drw.active
  ) or exists(
    select 1 from public.profiles
    where id=auth.uid() and role='worker' and active and job_title='REPLACEMENT'
  ) into v_is_replacement;

  return query
  select v_day_id,v_is_replacement,r.id,
    case when r.replacement_worker_id=auth.uid() then 'SUBSTITUTE' else 'REQUESTER' end,
    r.status,
    case when r.status='PENDING' then 1+(
      select count(*)::integer from public.replacement_requests q
      where q.day_id=r.day_id and q.replacement_worker_id=r.replacement_worker_id and q.status='PENDING'
        and (q.requested_at,q.id)<(r.requested_at,r.id)
    ) end,
    r.attraction_id,a.name,
    case when r.replacement_worker_id=auth.uid() then requester.display_name else substitute.display_name end,
    r.requested_at,r.accepted_at,r.due_at,
    case when r.status='ACTIVE' and r.due_at is not null then extract(epoch from (r.due_at-now()))::integer end,
    (r.status='ACTIVE' and r.due_at is not null and r.due_at<now())
  from public.replacement_requests r
  join public.attractions a on a.id=r.attraction_id
  join public.profiles requester on requester.id=r.requester_id
  join public.profiles substitute on substitute.id=r.replacement_worker_id
  where r.day_id=v_day_id
    and (r.requester_id=auth.uid() or r.replacement_worker_id=auth.uid())
    and r.status in ('PENDING','ACTIVE')
  order by case when r.status='ACTIVE' then 0 else 1 end,r.requested_at,r.id;

  if not found then
    return query select v_day_id,v_is_replacement,null::bigint,
      case when v_is_replacement then 'STANDBY' else 'AVAILABLE' end,null::text,null::integer,
      null::bigint,null::text,null::text,null::timestamptz,null::timestamptz,null::timestamptz,null::integer,false;
  end if;
end;
$function$;

revoke all on function public.worker_open_attractions_auto() from public;
revoke all on function public.begin_shift_auto(bigint) from public;
revoke all on function public.worker_request_replacement_auto(bigint) from public;
revoke all on function public.worker_replacement_queue_auto() from public;
grant execute on function public.worker_open_attractions_auto() to authenticated;
grant execute on function public.begin_shift_auto(bigint) to authenticated;
grant execute on function public.worker_request_replacement_auto(bigint) to authenticated;
grant execute on function public.worker_replacement_queue_auto() to authenticated;

commit;
