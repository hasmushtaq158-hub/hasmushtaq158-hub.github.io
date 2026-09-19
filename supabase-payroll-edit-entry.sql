-- Safe manager edit for one completed daily payroll record.
-- Run once in Supabase SQL Editor before using the new "Изменить" button.

begin;

drop function if exists public.manager_update_payroll_entry(bigint,time,time,text,numeric,numeric,text);

create or replace function public.manager_update_payroll_entry(
  p_entry_id bigint,
  p_started_time time,
  p_ended_time time,
  p_day_type text,
  p_bonus numeric default 0,
  p_deduction numeric default 0,
  p_note text default null
)
returns bigint
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_entry public.payroll_entries%rowtype;
  v_interval interval;
  v_minutes integer;
  v_rate numeric(10,2);
  v_base numeric(12,2);
  v_total numeric(12,2);
  v_attraction text;
  v_worker_name text;
begin
  if not public.park_is_manager() then raise exception 'MANAGER_REQUIRED'; end if;
  if p_day_type not in ('NORMAL','HOLIDAY') then raise exception 'INVALID_DAY_TYPE'; end if;
  if coalesce(p_bonus,0) < 0 or coalesce(p_deduction,0) < 0 then raise exception 'INVALID_ADJUSTMENT'; end if;

  select * into v_entry
  from public.payroll_entries
  where id=p_entry_id and status='ACTIVE'
  for update;

  if not found then raise exception 'ACTIVE_PAYROLL_ENTRY_NOT_FOUND'; end if;

  select name into v_attraction from public.attractions where id=v_entry.attraction_id;
  select display_name into v_worker_name from public.profiles where id=v_entry.worker_id;

  v_interval:=p_ended_time-p_started_time;
  if v_interval<=interval '0' then v_interval:=v_interval+interval '1 day'; end if;
  v_minutes:=round(extract(epoch from v_interval)/60)::integer;
  if v_minutes<=0 or v_minutes>960 then raise exception 'INVALID_WORK_DURATION'; end if;

  if position('кристин' in lower(coalesce(v_worker_name,'')))>0
     or position('марин' in lower(coalesce(v_worker_name,'')))>0 then
    v_rate:=200;
  elsif position('колесо победы' in lower(coalesce(v_attraction,'')))>0 then
    v_rate:=case when p_day_type='HOLIDAY' then 200 else 180 end;
  else
    v_rate:=case when p_day_type='HOLIDAY' then 180 else 150 end;
  end if;

  v_base:=round(v_minutes::numeric/60*v_rate,2);
  v_total:=round(v_base+coalesce(p_bonus,0)-coalesce(p_deduction,0),2);

  update public.payroll_entries
  set started_time=p_started_time,
      ended_time=p_ended_time,
      duration_minutes=v_minutes,
      day_type=p_day_type,
      hourly_rate=v_rate,
      base_amount=v_base,
      bonus=coalesce(p_bonus,0),
      deduction=coalesce(p_deduction,0),
      total_amount=v_total,
      note=coalesce(nullif(trim(p_note),''),note)
  where id=p_entry_id;

  return p_entry_id;
end;
$function$;

revoke all on function public.manager_update_payroll_entry(bigint,time,time,text,numeric,numeric,text) from public;
grant execute on function public.manager_update_payroll_entry(bigint,time,time,text,numeric,numeric,text) to authenticated;

commit;
