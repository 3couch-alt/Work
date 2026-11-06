-- Weekend Route Board: database setup for Supabase.
--
-- All tables live in the "private" schema, which the public API cannot
-- reach. The website only talks to the functions in "public" below:
--
--   get_board()        anyone   read routes, open dates and requests
--   submit_request()   anyone   ask for a route on a date
--   manager_login()    manager  check the passcode
--   decide_request()   manager  approve, decline or release a request
--   assign_route()     manager  give a route straight to someone
--   set_date_open()    manager  open or close a weekend date
--   add_route()        manager  put a route on the board
--   retire_route()     manager  take a route off the board
--   change_passcode()  manager  set a new manager passcode
--
-- Nothing is ever erased: closed dates and retired routes are hidden,
-- and request history is kept.

create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table private.routes (
  code        text primary key check (code ~ '^[A-Z0-9-]{2,20}$'),
  weekday     text not null check (weekday in ('Saturday', 'Sunday')),
  sort_order  int  not null default 0,
  active      boolean not null default true
);

create table private.open_dates (
  work_date date primary key check (extract(isodow from work_date) in (6, 7)),
  is_open   boolean not null default true
);

create table private.requests (
  id            uuid primary key default gen_random_uuid(),
  route_code    text not null references private.routes (code) on update cascade,
  work_date     date not null references private.open_dates (work_date),
  employee_name text not null check (char_length(employee_name) between 2 and 60),
  status        text not null default 'pending'
                check (status in ('pending', 'approved', 'declined', 'released')),
  created_at    timestamptz not null default now(),
  decided_at    timestamptz
);

-- Only one person can hold a route on a given date.
create unique index requests_one_approved_per_slot
  on private.requests (route_code, work_date)
  where status = 'approved';

-- The same person can't stack duplicate requests for the same route and date.
create unique index requests_no_duplicate_active
  on private.requests (route_code, work_date, lower(employee_name))
  where status in ('pending', 'approved');

create index requests_work_date_idx on private.requests (work_date);

create table private.manager_auth (
  id            int primary key default 1 check (id = 1),
  passcode_hash text not null
);

create table private.login_throttle (
  source       text primary key,
  window_start timestamptz not null default now(),
  failures     int not null default 0
);

-- ---------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------

create or replace function private.clean_name(p text)
returns text
language sql immutable
set search_path = ''
as $$
  select nullif(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g'), '')
$$;

create or replace function private.today()
returns date
language sql stable
set search_path = ''
as $$
  select (now() at time zone 'America/New_York')::date
$$;

create or replace function private.weekday_name(p date)
returns text
language sql immutable
set search_path = ''
as $$
  select case extract(isodow from p) when 6 then 'Saturday' when 7 then 'Sunday' end
$$;

create or replace function private.short_date(p date)
returns text
language sql immutable
set search_path = ''
as $$
  select to_char(p, 'Dy Mon FMDD')
$$;

create or replace function private.fail(p_message text)
returns jsonb
language sql immutable
set search_path = ''
as $$
  select jsonb_build_object('ok', false, 'error', p_message)
$$;

-- Who is calling, for counting wrong passcode guesses.
create or replace function private.request_source()
returns text
language plpgsql stable
set search_path = ''
as $$
declare
  h json;
begin
  begin
    h := current_setting('request.headers', true)::json;
  exception when others then
    h := null;
  end;
  return coalesce(
    nullif(btrim(h ->> 'cf-connecting-ip'), ''),
    nullif(btrim(h ->> 'x-real-ip'), ''),
    'unknown'
  );
end
$$;

-- NULL when the passcode is right, otherwise an error message.
-- Ten wrong guesses from one source lock it out for 15 minutes.
create or replace function private.passcode_error(p_passcode text)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_source text := private.request_source();
  v_row    private.login_throttle;
  v_hash   text;
begin
  select * into v_row from private.login_throttle where source = v_source;
  if found and v_row.window_start > now() - interval '15 minutes'
     and v_row.failures >= 10 then
    return 'Too many wrong passcodes. Wait 15 minutes and try again.';
  end if;

  select passcode_hash into v_hash from private.manager_auth where id = 1;
  if v_hash is null then
    return 'No manager passcode has been set up yet.';
  end if;

  if p_passcode is null or extensions.crypt(p_passcode, v_hash) <> v_hash then
    insert into private.login_throttle as t (source, window_start, failures)
    values (v_source, now(), 1)
    on conflict (source) do update
      set failures = case when t.window_start > now() - interval '15 minutes'
                          then t.failures + 1 else 1 end,
          window_start = case when t.window_start > now() - interval '15 minutes'
                              then t.window_start else now() end;
    return 'That manager passcode is wrong.';
  end if;

  return null;
end
$$;

-- ---------------------------------------------------------------------
-- Anyone: read the board
-- ---------------------------------------------------------------------

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
      select jsonb_agg(jsonb_build_object('code', code, 'weekday', weekday)
                       order by sort_order, code)
        from private.routes
       where active), '[]'::jsonb),
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
               'created_at', r.created_at,
               'decided_at', r.decided_at)
             order by r.created_at)
        from private.requests r
        join private.open_dates d on d.work_date = r.work_date and d.is_open
        join private.routes ro on ro.code = r.route_code and ro.active
       where r.work_date >= private.today() - 45), '[]'::jsonb)
  )
$$;

-- ---------------------------------------------------------------------
-- Anyone: request a route
-- ---------------------------------------------------------------------

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

-- ---------------------------------------------------------------------
-- Manager actions (all check the passcode first)
-- ---------------------------------------------------------------------

create or replace function public.manager_login(p_passcode text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_err text := private.passcode_error(p_passcode);
begin
  if v_err is not null then
    return private.fail(v_err);
  end if;
  return jsonb_build_object('ok', true);
end
$$;

-- p_action: 'approve' | 'decline' | 'release'
create or replace function public.decide_request(p_passcode text, p_request_id uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_err    text := private.passcode_error(p_passcode);
  v_req    private.requests;
  v_holder text;
  v_others int := 0;
begin
  if v_err is not null then
    return private.fail(v_err);
  end if;

  select * into v_req from private.requests where id = p_request_id for update;
  if not found then
    return private.fail('That request is no longer on the board.');
  end if;

  if p_action = 'approve' then
    if v_req.status = 'approved' then
      return jsonb_build_object('ok', true, 'declined_others', 0);
    end if;
    if v_req.status <> 'pending' then
      return private.fail('Only pending requests can be approved.');
    end if;
    select employee_name into v_holder
      from private.requests
     where route_code = v_req.route_code and work_date = v_req.work_date
       and status = 'approved';
    if found then
      return private.fail(format('%s already has %s on %s. Release it first.',
        v_holder, v_req.route_code, private.short_date(v_req.work_date)));
    end if;

    update private.requests set status = 'approved', decided_at = now()
     where id = v_req.id;

    -- Everyone else who asked for the same route and date is declined.
    update private.requests set status = 'declined', decided_at = now()
     where route_code = v_req.route_code and work_date = v_req.work_date
       and status = 'pending' and id <> v_req.id;
    get diagnostics v_others = row_count;

    return jsonb_build_object('ok', true, 'declined_others', v_others);

  elsif p_action = 'decline' then
    if v_req.status <> 'pending' then
      return private.fail('Only pending requests can be declined.');
    end if;
    update private.requests set status = 'declined', decided_at = now()
     where id = v_req.id;
    return jsonb_build_object('ok', true);

  elsif p_action = 'release' then
    if v_req.status <> 'approved' then
      return private.fail('Only approved routes can be released.');
    end if;
    update private.requests set status = 'released', decided_at = now()
     where id = v_req.id;
    return jsonb_build_object('ok', true);
  end if;

  return private.fail('Unknown action.');
end
$$;

-- Give a route straight to someone (for example, after a phone call).
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

  -- Reuse this person's pending request if they already asked.
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

-- Open or close a Saturday/Sunday for sign-ups.
create or replace function public.set_date_open(p_passcode text, p_date date, p_open boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_err      text := private.passcode_error(p_passcode);
  v_approved int;
begin
  if v_err is not null then
    return private.fail(v_err);
  end if;
  if p_date is null then
    return private.fail('Pick a date.');
  end if;

  if p_open then
    if private.weekday_name(p_date) is null then
      return private.fail('Pick a Saturday or a Sunday.');
    end if;
    insert into private.open_dates (work_date, is_open) values (p_date, true)
    on conflict (work_date) do update set is_open = true;
    return jsonb_build_object('ok', true);
  end if;

  select count(*) into v_approved
    from private.requests where work_date = p_date and status = 'approved';
  if v_approved > 0 then
    return private.fail(format('%s route(s) on %s are already approved. Release them first.',
      v_approved, private.short_date(p_date)));
  end if;

  update private.requests set status = 'declined', decided_at = now()
   where work_date = p_date and status = 'pending';
  update private.open_dates set is_open = false where work_date = p_date;
  return jsonb_build_object('ok', true);
end
$$;

-- Put a route on the board (or bring a retired one back).
create or replace function public.add_route(p_passcode text, p_code text, p_weekday text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_err  text := private.passcode_error(p_passcode);
  v_code text := upper(btrim(coalesce(p_code, '')));
  v_next int;
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
  if exists (select 1 from private.routes where code = v_code and active) then
    return private.fail(format('%s is already on the board.', v_code));
  end if;

  select coalesce(max(sort_order), 0) + 1 into v_next from private.routes;

  insert into private.routes (code, weekday, sort_order, active)
  values (v_code, p_weekday, v_next, true)
  on conflict (code) do update
    set weekday = excluded.weekday, sort_order = excluded.sort_order, active = true;
  return jsonb_build_object('ok', true);
end
$$;

-- Take a route off the board. Its history is kept.
create or replace function public.retire_route(p_passcode text, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_err      text := private.passcode_error(p_passcode);
  v_code     text := upper(btrim(coalesce(p_code, '')));
  v_approved int;
begin
  if v_err is not null then
    return private.fail(v_err);
  end if;
  if not exists (select 1 from private.routes where code = v_code and active) then
    return private.fail(format('%s is not on the board.', v_code));
  end if;

  select count(*) into v_approved
    from private.requests
   where route_code = v_code and status = 'approved' and work_date >= private.today();
  if v_approved > 0 then
    return private.fail(format('%s has %s upcoming approved date(s). Release them first.',
      v_code, v_approved));
  end if;

  update private.requests set status = 'declined', decided_at = now()
   where route_code = v_code and status = 'pending';
  update private.routes set active = false where code = v_code;
  return jsonb_build_object('ok', true);
end
$$;

create or replace function public.change_passcode(p_passcode text, p_new_passcode text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_err text := private.passcode_error(p_passcode);
begin
  if v_err is not null then
    return private.fail(v_err);
  end if;
  if p_new_passcode is null or char_length(p_new_passcode) < 8 then
    return private.fail('Use at least 8 characters for the new passcode.');
  end if;

  update private.manager_auth
     set passcode_hash = extensions.crypt(p_new_passcode, extensions.gen_salt('bf'))
   where id = 1;
  return jsonb_build_object('ok', true);
end
$$;
