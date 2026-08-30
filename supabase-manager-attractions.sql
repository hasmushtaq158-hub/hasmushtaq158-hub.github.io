-- Safe manager-only create/update path for attractions.
create or replace function public.manager_save_attraction(
  p_attraction_id bigint,
  p_name text,
  p_price integer,
  p_active boolean default true
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
  v_name text := btrim(coalesce(p_name, ''));
begin
  if not public.park_is_manager() then
    raise exception 'Manager access required';
  end if;

  if v_name = '' then
    raise exception 'Attraction name is required';
  end if;
  if p_price is null or p_price < 0 then
    raise exception 'Price must be zero or greater';
  end if;

  if p_attraction_id is null then
    insert into public.attractions (name, price, active, updated_at)
    values (v_name, p_price, coalesce(p_active, true), now())
    returning id into v_id;
  else
    update public.attractions
       set name = v_name,
           price = p_price,
           active = coalesce(p_active, true),
           updated_at = now()
     where id = p_attraction_id
     returning id into v_id;

    if v_id is null then
      raise exception 'Attraction not found';
    end if;
  end if;

  return v_id;
end;
$$;

revoke all on function public.manager_save_attraction(bigint, text, integer, boolean) from public;
grant execute on function public.manager_save_attraction(bigint, text, integer, boolean) to authenticated;
