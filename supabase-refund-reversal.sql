create or replace function public.manager_reverse_refund(
  p_ticket_id bigint,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_request_id bigint;
begin
  if not public.park_is_manager() then
    raise exception 'MANAGER_REQUIRED';
  end if;

  perform 1
  from public.tickets
  where id = p_ticket_id
    and status = 'REFUNDED'
  for update;

  if not found then
    raise exception 'TICKET_NOT_REFUNDED';
  end if;

  select id
  into v_request_id
  from public.refund_requests
  where ticket_id = p_ticket_id
    and status = 'APPROVED'
  order by resolved_at desc nulls last, id desc
  limit 1
  for update;

  if v_request_id is null then
    raise exception 'APPROVED_REFUND_NOT_FOUND';
  end if;

  update public.tickets
  set status = 'VALID'
  where id = p_ticket_id;

  update public.refund_requests
  set status = 'REJECTED',
      resolved_at = now(),
      resolved_by = auth.uid(),
      resolution_note = coalesce(
        nullif(trim(p_note), ''),
        'Возврат отменён: посетитель решил воспользоваться билетом'
      )
  where id = v_request_id;
end;
$function$;

grant execute on function public.manager_reverse_refund(bigint, text) to authenticated;
