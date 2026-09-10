begin;

-- Repair every historical fine, including the latest 150 ₽ fine for Моторкин.
-- Cancelled records remain excluded by the payroll functions, so no cancelled
-- fine is charged and each active fine is counted only once.
update public.worker_notices
set deduct_from_salary = true
where notice_type = 'PENALTY' and not deduct_from_salary;

alter table public.worker_notices
  alter column deduct_from_salary set default true;

create or replace function public.enforce_worker_notice_payroll_rule()
returns trigger
language plpgsql
set search_path = public
as $function$
begin
  if new.notice_type = 'PENALTY' then
    new.deduct_from_salary := true;
  else
    new.amount := 0;
    new.deduct_from_salary := false;
  end if;
  return new;
end;
$function$;

drop trigger if exists enforce_worker_notice_payroll_rule_trigger on public.worker_notices;
create trigger enforce_worker_notice_payroll_rule_trigger
before insert or update of notice_type,deduct_from_salary,amount on public.worker_notices
for each row execute function public.enforce_worker_notice_payroll_rule();

create or replace function public.manager_create_worker_notice(
  p_worker_id uuid,
  p_notice_type text,
  p_message text,
  p_amount numeric default 0,
  p_deduct_from_salary boolean default false
)
returns bigint
language plpgsql
security definer
set search_path = public
as $function$
declare v_id bigint;
begin
  if not public.park_is_manager() then raise exception 'MANAGER_REQUIRED'; end if;
  if p_notice_type not in ('SAFETY','PENALTY') then raise exception 'INVALID_NOTICE_TYPE'; end if;
  if char_length(trim(coalesce(p_message,''))) < 3 then raise exception 'MESSAGE_REQUIRED'; end if;
  if p_notice_type = 'SAFETY' then
    p_amount := 0;
    p_deduct_from_salary := false;
  else
    p_deduct_from_salary := true;
  end if;
  if coalesce(p_amount,0) < 0 then raise exception 'INVALID_AMOUNT'; end if;
  if not exists(select 1 from public.profiles where id=p_worker_id and role='worker' and active) then
    raise exception 'WORKER_NOT_FOUND';
  end if;
  insert into public.worker_notices(worker_id,notice_type,message,amount,deduct_from_salary,created_by)
  values(p_worker_id,p_notice_type,trim(p_message),coalesce(p_amount,0),p_deduct_from_salary,auth.uid())
  returning id into v_id;
  return v_id;
end;
$function$;

grant execute on function public.manager_create_worker_notice(uuid,text,text,numeric,boolean) to authenticated;

commit;
