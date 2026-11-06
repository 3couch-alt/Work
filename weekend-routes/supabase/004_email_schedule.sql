-- Weekend Route Board: hourly email job.
--
-- Runs at 7 minutes past every hour. It sends evening-before reminders
-- (from 5 PM Eastern) and catches any alert or notice the page didn't
-- trigger itself, for example when someone closed the page mid-send.

create extension if not exists pg_cron with schema pg_catalog;

grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

select cron.schedule(
  'weekend-routes-email',
  '7 * * * *',
  'select private.flush_notifications()'
);
