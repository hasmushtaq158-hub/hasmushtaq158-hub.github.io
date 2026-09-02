-- One-time correction requested on 2026-09-02.
-- 01.09.2026 is a holiday-rate day for everyone.
-- Кристианой Марина always receives 200 RUB/hour; her compensating bonus is removed.
with target as (
  select e.id,e.status,e.duration_minutes,e.bonus,e.deduction,
         coalesce(p.display_name,pp.display_name,'') worker_name,
         coalesce(a.name,'') attraction_name
  from public.payroll_entries e
  left join public.profiles p on p.id=e.worker_id
  left join public.payroll_people pp on pp.id=e.payroll_person_id
  left join public.attractions a on a.id=e.attraction_id
  where e.work_date=date '2026-09-01' and e.status in ('OPEN','ACTIVE')
), rates as (
  select *,
         position('кристиан' in lower(worker_name))>0 and position('марин' in lower(worker_name))>0 as is_marina,
         case
           when position('кристиан' in lower(worker_name))>0 and position('марин' in lower(worker_name))>0 then 200
           when position('колесо победы' in lower(attraction_name))>0 then 200
           else 180
         end::numeric rate
  from target
), changed as (
  update public.payroll_entries e set
    day_type='HOLIDAY',
    hourly_rate=case when r.status='ACTIVE' then r.rate else e.hourly_rate end,
    base_amount=case when r.status='ACTIVE' then round(r.duration_minutes::numeric/60*r.rate,2) else e.base_amount end,
    bonus=case when r.is_marina then 0 else e.bonus end,
    total_amount=case when r.status='ACTIVE' then round(r.duration_minutes::numeric/60*r.rate + case when r.is_marina then 0 else coalesce(r.bonus,0) end - coalesce(r.deduction,0),2) else e.total_amount end
  from rates r where e.id=r.id
  returning e.id,e.status
)
select count(*) updated_workers,
       count(*) filter(where status='ACTIVE') recalculated,
       count(*) filter(where status='OPEN') still_working
from changed;
