-- Weekend Route Board: route details.
--
-- The manager can give each route a start time, a place to report, the area
-- it covers, notes, and up to 8 extra details of their own (a name and a
-- value, such as "Vehicle: Van 12"). Drivers see them on the board.
--
--   save_route()  manager  add a route with details, or change an existing one

create table private.route_details (
  code       text primary key references private.routes (code) on update cascade,
  start_time time,
  location   text check (location is null or char_length(location) <= 120),
  area       text check (area is null or char_length(area) <= 200),
  notes      text check (notes is null or char_length(notes) <= 500),
  extras     jsonb not null default '[]'::jsonb
             check (jsonb_typeof(extras) = 'array' and jsonb_array_length(extras) <= 8),
  updated_at timestamptz not null default now()
);

-- p_is_new: true when the manager used "Add a route", false when editing.
-- p_extras: a JSON array of {"label": ..., "value": ...}.
create or replace function public.save_route(
  p_passcode   text,
  p_code       text,
  p_weekday    text,
  p_start_time text,
  p_location   text,
  p_area       text,
  p_notes      text,
  p_extras     jsonb,
  p_is_new     boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_err       text := private.passcode_error(p_passcode);
  v_code      text := upper(btrim(coalesce(p_code, '')));
  v_location  text := nullif(btrim(coalesce(p_location, '')), '');
  v_area      text := nullif(btrim(coalesce(p_area, '')), '');
  v_notes     text := nullif(btrim(coalesce(p_notes, '')), '');
  v_start     time;
  v_extras    jsonb := '[]'::jsonb;
  v_item      jsonb;
  v_label     text;
  v_value     text;
  v_route     private.routes;
  v_conflicts int;
  v_created   boolean := false;
begin
  if v_err is not null then
    return private.fail(v_err);
  end if;
  if v_code !~ '^[A-Z0-9-]{2,20}$' then
    return private.fail('Route codes use letters, numbers and dashes, like SCCOL26.');
  end if;
  if p_weekday is null or p_weekday not in ('Saturday', 'Sunday') then
    return private.fail('Pick Saturday or Sunday.');
  end if;

  if nullif(btrim(coalesce(p_start_time, '')), '') is not null then
    begin
      v_start := btrim(p_start_time)::time;
    exception when others then
      return private.fail('Use a start time like 6:30 AM.');
    end;
  end if;

  if char_length(v_location) > 120 then
    return private.fail('Keep "Report to" under 120 characters.');
  end if;
  if char_length(v_area) > 200 then
    return private.fail('Keep "Area covered" under 200 characters.');
  end if;
  if char_length(v_notes) > 500 then
    return private.fail('Keep notes under 500 characters.');
  end if;

  if p_extras is not null and jsonb_typeof(p_extras) = 'array' then
    for v_item in select * from jsonb_array_elements(p_extras) loop
      v_label := nullif(btrim(coalesce(v_item ->> 'label', '')), '');
      v_value := nullif(btrim(coalesce(v_item ->> 'value', '')), '');
      continue when v_label is null and v_value is null;
      if v_label is null or v_value is null then
        return private.fail('Each extra detail needs both a name and a value.');
      end if;
      if char_length(v_label) > 40 or char_length(v_value) > 200 then
        return private.fail('Keep detail names under 40 characters and values under 200.');
      end if;
      v_extras := v_extras || jsonb_build_array(jsonb_build_object('label', v_label, 'value', v_value));
    end loop;
  end if;
  if jsonb_array_length(v_extras) > 8 then
    return private.fail('A route can have up to 8 extra details.');
  end if;

  select * into v_route from private.routes where code = v_code;

  if found and v_route.active then
    if p_is_new then
      return private.fail(format('%s is already on the board. Use Edit to change it.', v_code));
    end if;
    if v_route.weekday <> p_weekday then
      select count(*) into v_conflicts
        from private.requests
       where route_code = v_code
         and status in ('pending', 'approved')
         and work_date >= private.today();
      if v_conflicts > 0 then
        return private.fail(format(
          '%s has %s open request(s) on %ss. Decline or release them before moving it to %ss.',
          v_code, v_conflicts, v_route.weekday, p_weekday));
      end if;
      update private.routes set weekday = p_weekday where code = v_code;
    end if;
  else
    -- A new route, or a retired one coming back.
    insert into private.routes (code, weekday, sort_order, active)
    values (v_code, p_weekday,
            (select coalesce(max(sort_order), 0) + 1 from private.routes), true)
    on conflict (code) do update
      set weekday = excluded.weekday, sort_order = excluded.sort_order, active = true;
    v_created := true;
  end if;

  insert into private.route_details (code, start_time, location, area, notes, extras, updated_at)
  values (v_code, v_start, v_location, v_area, v_notes, v_extras, now())
  on conflict (code) do update
    set start_time = excluded.start_time,
        location   = excluded.location,
        area       = excluded.area,
        notes      = excluded.notes,
        extras     = excluded.extras,
        updated_at = now();

  return jsonb_build_object('ok', true, 'created', v_created);
end
$$;

-- The board now includes each route's details.
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
