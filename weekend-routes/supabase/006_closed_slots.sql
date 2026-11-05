-- Weekend Route Board: close a route for one day.
--
-- The manager can mark a route as not running on a given date. The board
-- shows it as Closed and nobody can request it. Closing declines any pending
-- requests for that route and day; it is refused while someone holds it.
-- Assigning someone to a closed route-day reopens it.
--
--   set_slot_closed()  manager  close or reopen one route on one date

create table private.slot_closures (
  route_code text not null references private.routes (code) on update cascade,
  work_date  date not null references private.open_dates (work_date),
  is_closed  boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (route_code, work_date)
);

create or replace function public.set_slot_closed(
  p_passcode text, p_route text, p_date date, p_closed boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_err      text := private.passcode_error(p_passcode);
  v_route    private.routes;
  v_holder   text;
  v_declined int := 0;
begin
  if v_err is not null then
    return private.fail(v_err);
  end if;

  select * into v_route from private.routes
   where code = upper(btrim(coalesce(p_route, ''))) and active;
  if not found then
    return private.fail('That route is not on the board.');
  end if;
  if p_date is null or not exists (select 1 from private.open_dates
                                    where work_date = p_date and is_open) then
    return private.fail('That date is not on the board.');
  end if;
  if private.weekday_name(p_date) <> v_route.weekday then
    return private.fail(format('%s only runs on %ss.', v_route.code, v_route.weekday));
  end if;

  if coalesce(p_closed, true) then
    select employee_name into v_holder
      from private.requests
     where route_code = v_route.code and work_date = p_date and status = 'approved';
    if found then
      return private.fail(format('%s has %s on %s. Release it before closing it.',
        v_holder, v_route.code, private.short_date(p_date)));
    end if;

    update private.requests set status = 'declined', decided_at = now()
     where route_code = v_route.code and work_date = p_date and status = 'pending';
    get diagnostics v_declined = row_count;
  end if;

  insert into private.slot_closures (route_code, work_date, is_closed, updated_at)
  values (v_route.code, p_date, coalesce(p_closed, true), now())
  on conflict (route_code, work_date) do update
    set is_closed = excluded.is_closed, updated_at = now();

  return jsonb_build_object('ok', true, 'declined', v_declined);
end
$$;

-- Requests for a closed route-day are refused.
create or replace function public.submit_request(p_route text, p_date date, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name  text := private.clean_name(p_name);
  v_route private.routes;
  v_taken text;
  v_id    uuid;
begin
  if v_name is null or char_length(v_name) < 2 then
    return private.fail('Enter your name first.');
  end if;
  if char_length(v_name) > 60 then
    return private.fail('That name is too long (60 characters max).');
  end if;

  select * into v_route from private.routes
   where code = upper(btrim(p_route)) and active;
  if not found then
    return private.fail('That route is no longer on the board.');
  end if;

  if not exists (select 1 from private.open_dates
                  where work_date = p_date and is_open) then
    return private.fail('That date is no longer open for sign-ups.');
  end if;
  if p_date < private.today() then
    return private.fail('That date has already passed.');
  end if;
  if private.weekday_name(p_date) <> v_route.weekday then
    return private.fail(format('%s only runs on %ss.', v_route.code, v_route.weekday));
  end if;
  if exists (select 1 from private.slot_closures
              where route_code = v_route.code and work_date = p_date and is_closed) then
    return private.fail(format('%s is closed on %s.', v_route.code, private.short_date(p_date)));
  end if;

  select employee_name into v_taken
    from private.requests
   where route_code = v_route.code and work_date = p_date and status = 'approved';
  if found then
    return private.fail(format('%s on %s is already taken by %s.',
      v_route.code, private.short_date(p_date), v_taken));
  end if;

  if exists (select 1 from private.requests
              where route_code = v_route.code and work_date = p_date
                and status = 'pending' and lower(employee_name) = lower(v_name)) then
    return private.fail(format('%s already asked for %s on %s.',
      v_name, v_route.code, private.short_date(p_date)));
  end if;

  insert into private.requests (route_code, work_date, employee_name)
  values (v_route.code, p_date, v_name)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end
$$;

-- Assigning someone to a closed route-day reopens it.
create or replace function public.assign_route(p_passcode text, p_route text, p_date date, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_err    text := private.passcode_error(p_passcode);
  v_name   text := private.clean_name(p_name);
  v_route  private.routes;
  v_holder text;
  v_id     uuid;
  v_others int := 0;
begin
  if v_err is not null then
    return private.fail(v_err);
  end if;
  if v_name is null or char_length(v_name) < 2 or char_length(v_name) > 60 then
    return private.fail('Enter the person''s name (2 to 60 characters).');
  end if;

  select * into v_route from private.routes
   where code = upper(btrim(p_route)) and active;
  if not found then
    return private.fail('That route is not on the board.');
  end if;
  if not exists (select 1 from private.open_dates
                  where work_date = p_date and is_open) then
    return private.fail('That date is not on the board. Open it under Dates first.');
  end if;
  if private.weekday_name(p_date) <> v_route.weekday then
    return private.fail(format('%s only runs on %ss.', v_route.code, v_route.weekday));
  end if;

  select employee_name into v_holder
    from private.requests
   where route_code = v_route.code and work_date = p_date and status = 'approved';
  if found then
    return private.fail(format('%s already has %s on %s. Release it first.',
      v_holder, v_route.code, private.short_date(p_date)));
  end if;

  update private.slot_closures set is_closed = false, updated_at = now()
   where route_code = v_route.code and work_date = p_date and is_closed;

  select id into v_id
    from private.requests
   where route_code = v_route.code and work_date = p_date
     and status = 'pending' and lower(employee_name) = lower(v_name);

  if v_id is not null then
    update private.requests set status = 'approved', decided_at = now()
     where id = v_id;
  else
    insert into private.requests (route_code, work_date, employee_name, status, decided_at)
    values (v_route.code, p_date, v_name, 'approved', now())
    returning id into v_id;
  end if;

  update private.requests set status = 'declined', decided_at = now()
   where route_code = v_route.code and work_date = p_date
     and status = 'pending' and id <> v_id;
  get diagnostics v_others = row_count;

  return jsonb_build_object('ok', true, 'id', v_id, 'declined_others', v_others);
end
$$;

-- The board now also lists closed route-days.
create or replace function public.get_board()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'today', private.today(),
    'routes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code', r.code,
               'weekday', r.weekday,
               'start', to_char(d.start_time, 'HH24:MI'),
               'location', d.location,
               'area', d.area,
               'notes', d.notes,
               'extras', coalesce(d.extras, '[]'::jsonb))
             order by r.sort_order, r.code)
        from private.routes r
        left join private.route_details d on d.code = r.code
       where r.active), '[]'::jsonb),
    'dates', coalesce((
      select jsonb_agg(work_date order by work_date)
        from private.open_dates
       where is_open and work_date >= private.today() - 45), '[]'::jsonb),
    'closed', coalesce((
      select jsonb_agg(jsonb_build_object('route', route_code, 'date', work_date)
                       order by work_date, route_code)
        from private.slot_closures
       where is_closed and work_date >= private.today() - 45), '[]'::jsonb),
    'requests', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id,
               'route', r.route_code,
               'date', r.work_date,
               'name', r.employee_name,
               'status', r.status,
               'remind', coalesce(c.remind, false),
               'created_at', r.created_at,
               'decided_at', r.decided_at)
             order by r.created_at)
        from private.requests r
        join private.open_dates d on d.work_date = r.work_date and d.is_open
        join private.routes ro on ro.code = r.route_code and ro.active
        left join private.request_contacts c on c.request_id = r.id
       where r.work_date >= private.today() - 45), '[]'::jsonb)
  )
$$;
