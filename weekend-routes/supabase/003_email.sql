-- Weekend Route Board: email notifications.
--
--   * A driver can add an email to a request. They are emailed when it is
--     approved, declined or released, and, if they ask, reminded the evening
--     before an approved route.
--   * The supervisor gets one email covering each batch of new requests.
--
-- Emails go out through a Google Apps Script web app that sends from the
-- owner's Gmail (see ../mailer/Code.gs). Its link and shared key live in
-- private.mail_settings and are never sent to the page. The key is set
-- separately and is not stored in this repository.
--
-- public.flush_notifications() sends whatever is due. The page calls it after
-- each batch of requests and after each manager action, and an hourly job
-- (004_email_schedule.sql) calls it as a safety net and for reminders.

create extension if not exists pg_net;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table private.mail_settings (
  id               int primary key default 1 check (id = 1),
  supervisor_email text check (supervisor_email is null
                               or supervisor_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  mailer_url       text check (mailer_url is null
                               or mailer_url ~ '^https://script\.google\.com/macros/s/[A-Za-z0-9_-]+/exec$'),
  mailer_token     text,
  site_url         text not null default 'https://sccol-weekend-routes.vercel.app'
);
insert into private.mail_settings (id) values (1) on conflict (id) do nothing;

-- One row per request that came with an email address.
create table private.request_contacts (
  request_id       uuid primary key references private.requests (id),
  email            text not null check (char_length(email) <= 254
                                        and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  remind           boolean not null default false,
  notified_status  text,
  reminder_sent_at timestamptz
);

-- Which requests the supervisor has already been told about.
create table private.supervisor_alerts (
  request_id uuid primary key references private.requests (id),
  handled_at timestamptz not null default now(),
  emailed    boolean not null
);

-- Requests made before email existed never trigger an alert.
insert into private.supervisor_alerts (request_id, emailed)
select id, false from private.requests
on conflict (request_id) do nothing;

create table private.mail_log (
  id             bigint generated always as identity primary key,
  queued_at      timestamptz not null default now(),
  kind           text not null,
  to_email       text not null,
  subject        text not null,
  net_request_id bigint
);
create index mail_log_queued_idx on private.mail_log (queued_at desc);

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

create or replace function private.valid_email(p text)
returns boolean
language sql immutable
set search_path = ''
as $$
  select p is not null and char_length(p) <= 254 and p ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
$$;

create or replace function private.long_date(p date)
returns text
language sql immutable
set search_path = ''
as $$
  select to_char(p, 'FMDay, Mon FMDD')
$$;

create or replace function private.first_name(p text)
returns text
language sql immutable
set search_path = ''
as $$
  select split_part(btrim(p), ' ', 1)
$$;

create or replace function private.local_hour()
returns int
language sql stable
set search_path = ''
as $$
  select extract(hour from now() at time zone 'America/New_York')::int
$$;

-- Hands one email to the Gmail sender. Returns the pg_net request id, or
-- NULL when the sender isn't set up yet.
create or replace function private.queue_mail(
  p_kind text, p_to text, p_subject text, p_text text, p_reply_to text default null)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  s    private.mail_settings;
  v_id bigint;
begin
  select * into s from private.mail_settings where id = 1;
  if s.mailer_url is null or s.mailer_token is null then
    return null;
  end if;

  v_id := net.http_post(
    url := s.mailer_url,
    body := jsonb_build_object(
      'token',    s.mailer_token,
      'to',       p_to,
      'subject',  p_subject,
      'text',     p_text,
      'replyTo',  p_reply_to,
      'fromName', 'SCCOL Weekend Routes'),
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 15000
  );

  insert into private.mail_log (kind, to_email, subject, net_request_id)
  values (p_kind, p_to, p_subject, v_id);
  return v_id;
end
$$;

-- ---------------------------------------------------------------------
-- Send everything that is due
-- ---------------------------------------------------------------------

create or replace function private.flush_notifications()
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  s           private.mail_settings;
  v_count     int;
  v_people    int;
  v_name      text;
  v_what      text;
  v_body      text;
  v_subject   text;
  v_batch     jsonb;
  v_alerts    int := 0;
  v_notices   int := 0;
  v_reminders int := 0;
  rec         record;
begin
  -- Lock the settings row so two calls never send the same email twice.
  select * into s from private.mail_settings where id = 1 for update;
  if s.mailer_url is null or s.mailer_token is null then
    return jsonb_build_object('ok', true, 'sent', 0, 'note', 'Email is not set up yet.');
  end if;

  -- 1. Supervisor alert: one email for every new request from a driver.
  --    Routes the manager assigned directly (decided the moment they were
  --    created) are skipped.
  with due as (
    insert into private.supervisor_alerts (request_id, emailed)
    select r.id, s.supervisor_email is not null
      from private.requests r
     where not exists (select 1 from private.supervisor_alerts a where a.request_id = r.id)
       and (r.decided_at is null or r.decided_at <> r.created_at)
    on conflict (request_id) do nothing
    returning request_id
  ), batch as (
    select r.* from private.requests r join due on due.request_id = r.id
  )
  select count(*),
         count(distinct lower(employee_name)),
         min(employee_name),
         min(route_code || ' on ' || private.short_date(work_date)),
         (select string_agg(block, E'\n\n' order by first_at)
            from (select min(b.created_at) as first_at,
                         b.employee_name || E'\n' ||
                         string_agg('  - ' || b.route_code || ' on ' || private.long_date(b.work_date),
                                    E'\n' order by b.work_date, b.route_code) as block
                    from batch b
                   group by b.employee_name) blocks)
    into v_count, v_people, v_name, v_what, v_body
    from batch;

  if v_count > 0 and s.supervisor_email is not null then
    v_subject := case
      when v_count = 1  then v_name || ' requested ' || v_what
      when v_people = 1 then v_name || ' requested ' || v_count || ' routes'
      else v_count || ' new route requests from ' || v_people || ' people'
    end;
    perform private.queue_mail('alert', s.supervisor_email, v_subject,
      'New weekend route requests:' || E'\n\n' || v_body || E'\n\n' ||
      'Approve or decline them here:' || E'\n' || s.site_url || '/#manager');
    v_alerts := 1;
  end if;

  -- 2. Approved / declined / released notices, one email per address.
  with changed as (
    update private.request_contacts c
       set notified_status = r.status
      from private.requests r
     where r.id = c.request_id
       and r.status in ('approved', 'declined', 'released')
       and r.status is distinct from c.notified_status
    returning c.email, c.remind, r.employee_name, r.route_code, r.work_date, r.status
  )
  select jsonb_agg(jsonb_build_object(
           'email', email, 'name', name, 'n', n, 'lines', lines,
           'one', one, 'remind', any_remind))
    into v_batch
    from (select email,
                 min(employee_name) as name,
                 count(*) as n,
                 bool_or(remind and status = 'approved') as any_remind,
                 string_agg(case status
                              when 'approved' then 'Approved: '
                              when 'declined' then 'Not approved: '
                              else 'Released, no longer yours: '
                            end || route_code || ' on ' || private.long_date(work_date),
                            E'\n' order by work_date, route_code) as lines,
                 min(case status
                       when 'approved' then 'Approved: '
                       when 'declined' then 'Not approved: '
                       else 'Released: '
                     end || route_code || ' on ' || private.short_date(work_date)) as one
            from changed
           group by email) per_person;

  for rec in
    select * from jsonb_to_recordset(coalesce(v_batch, '[]'::jsonb))
      as t(email text, name text, n int, lines text, one text, remind boolean)
  loop
    perform private.queue_mail('decision', rec.email,
      case when rec.n = 1 then rec.one else 'Update on your weekend route requests' end,
      'Hi ' || private.first_name(rec.name) || ',' || E'\n\n' ||
      rec.lines || E'\n\n' ||
      case when rec.remind
           then 'You''ll get a reminder the evening before each approved route.' || E'\n\n'
           else '' end ||
      'See the board: ' || s.site_url,
      s.supervisor_email);
    v_notices := v_notices + 1;
  end loop;

  -- 3. Evening-before reminders, from 5 PM Eastern on.
  if private.local_hour() >= 17 then
    with due as (
      update private.request_contacts c
         set reminder_sent_at = now()
        from private.requests r
       where r.id = c.request_id
         and c.remind
         and c.reminder_sent_at is null
         and r.status = 'approved'
         and r.work_date = private.today() + 1
      returning c.email, r.employee_name, r.route_code, r.work_date
    )
    select jsonb_agg(jsonb_build_object('email', email, 'name', name, 'routes', routes, 'day', work_date))
      into v_batch
      from (select email, work_date,
                   min(employee_name) as name,
                   string_agg(route_code, ' and ' order by route_code) as routes
              from due
             group by email, work_date) per_person;

    for rec in
      select * from jsonb_to_recordset(coalesce(v_batch, '[]'::jsonb))
        as t(email text, name text, routes text, day date)
    loop
      perform private.queue_mail('reminder', rec.email,
        'Reminder: ' || rec.routes || ' tomorrow (' || private.short_date(rec.day) || ')',
        'Hi ' || private.first_name(rec.name) || ',' || E'\n\n' ||
        'This is your reminder that you''re working ' || rec.routes || ' tomorrow, ' ||
        private.long_date(rec.day) || '.' || E'\n\n' ||
        'If you can''t make it, let your manager know as soon as you can.' || E'\n\n' ||
        'See the board: ' || s.site_url,
        s.supervisor_email);
      v_reminders := v_reminders + 1;
    end loop;
  end if;

  return jsonb_build_object('ok', true, 'alerts', v_alerts,
                            'notices', v_notices, 'reminders', v_reminders);
end
$$;

-- ---------------------------------------------------------------------
-- Anyone: send what is due (safe to call any time; it only sends due mail)
-- ---------------------------------------------------------------------

create or replace function public.flush_notifications()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.flush_notifications()
$$;

-- ---------------------------------------------------------------------
-- Anyone: request a route, optionally with an email address
-- ---------------------------------------------------------------------

create or replace function public.request_route(
  p_route text, p_date date, p_name text, p_email text, p_remind boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_res   jsonb;
begin
  if v_email is not null and not private.valid_email(v_email) then
    return private.fail('That email address doesn''t look right.');
  end if;

  v_res := public.submit_request(p_route, p_date, p_name);

  if (v_res ->> 'ok')::boolean and v_email is not null then
    insert into private.request_contacts (request_id, email, remind)
    values ((v_res ->> 'id')::uuid, v_email, coalesce(p_remind, false));
  end if;

  return v_res;
end
$$;

-- The board now also says which requests have an email reminder set.
-- Email addresses themselves are never included.
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

-- ---------------------------------------------------------------------
-- Manager: email settings
-- ---------------------------------------------------------------------

create or replace function public.manager_mail_status(p_passcode text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_err text := private.passcode_error(p_passcode);
  s     private.mail_settings;
begin
  if v_err is not null then
    return private.fail(v_err);
  end if;
  select * into s from private.mail_settings where id = 1;

  return jsonb_build_object(
    'ok', true,
    'alert_email', s.supervisor_email,
    'link_saved', s.mailer_url is not null,
    'key_saved', s.mailer_token is not null,
    'recent', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.queued_at desc)
        from (select l.queued_at, l.kind, l.to_email, l.subject,
                     h.status_code, h.timed_out, h.error_msg,
                     left(h.content, 300) as content
                from private.mail_log l
                left join net._http_response h on h.id = l.net_request_id
               order by l.queued_at desc
               limit 6) x), '[]'::jsonb)
  );
end
$$;

-- Where new-request alerts go. An empty address turns alerts off.
create or replace function public.set_alert_email(p_passcode text, p_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_err   text := private.passcode_error(p_passcode);
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
begin
  if v_err is not null then
    return private.fail(v_err);
  end if;
  if v_email is not null and not private.valid_email(v_email) then
    return private.fail('That email address doesn''t look right.');
  end if;
  update private.mail_settings set supervisor_email = v_email where id = 1;
  return jsonb_build_object('ok', true, 'alert_email', v_email);
end
$$;

-- The Apps Script web app link (ends in /exec).
create or replace function public.set_mailer_link(p_passcode text, p_url text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_err   text := private.passcode_error(p_passcode);
  v_url   text := btrim(coalesce(p_url, ''));
  v_ready boolean;
begin
  if v_err is not null then
    return private.fail(v_err);
  end if;
  if v_url !~ '^https://script\.google\.com/macros/s/[A-Za-z0-9_-]+/exec$' then
    return private.fail('Paste the Web app URL from Apps Script. It starts with https://script.google.com/macros/s/ and ends with /exec.');
  end if;

  select mailer_url is not null into v_ready from private.mail_settings where id = 1;
  update private.mail_settings set mailer_url = v_url where id = 1;

  -- First time email is switched on: start fresh instead of emailing
  -- everything that happened before.
  if not v_ready then
    insert into private.supervisor_alerts (request_id, emailed)
    select id, false from private.requests
    on conflict (request_id) do nothing;

    update private.request_contacts c
       set notified_status = r.status
      from private.requests r
     where r.id = c.request_id
       and r.status in ('approved', 'declined', 'released')
       and r.status is distinct from c.notified_status;
  end if;

  return jsonb_build_object('ok', true);
end
$$;

create or replace function public.send_test_email(p_passcode text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_err text := private.passcode_error(p_passcode);
  s     private.mail_settings;
begin
  if v_err is not null then
    return private.fail(v_err);
  end if;
  select * into s from private.mail_settings where id = 1;
  if s.mailer_url is null then
    return private.fail('Save the Gmail sender link first.');
  end if;
  if s.mailer_token is null then
    return private.fail('The sender key is missing. Ask whoever set up the site to add it.');
  end if;
  if s.supervisor_email is null then
    return private.fail('Save an alert email first. The test goes there.');
  end if;

  perform private.queue_mail('test', s.supervisor_email,
    'Test email from SCCOL weekend routes',
    'This is a test from the weekend route board.' || E'\n\n' ||
    'If you can read this, new-request alerts will reach this address.' || E'\n\n' ||
    s.site_url || '/#manager');
  return jsonb_build_object('ok', true, 'to', s.supervisor_email);
end
$$;
