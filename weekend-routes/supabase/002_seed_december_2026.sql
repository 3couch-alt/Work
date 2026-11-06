-- December 2026 weekend routes, from the Support Services email.

insert into private.routes (code, weekday, sort_order) values
  ('SCCOL26', 'Saturday', 1),
  ('SCCOL27', 'Saturday', 2),
  ('SCCOL59', 'Saturday', 3),
  ('SCCOL61', 'Saturday', 4),
  ('SCCOL29', 'Sunday',   5),
  ('SCCOL60', 'Sunday',   6),
  ('SCCOL30', 'Sunday',   7)
on conflict (code) do nothing;

insert into private.open_dates (work_date) values
  ('2026-12-05'), ('2026-12-06'),
  ('2026-12-12'), ('2026-12-13'),
  ('2026-12-19'), ('2026-12-20'),
  ('2026-12-26'), ('2026-12-27')
on conflict (work_date) do nothing;
