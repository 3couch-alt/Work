# SCCOL Weekend Routes

A sign-up board for weekend routes. Coworkers open the link, tap the routes and dates they
want, and send a request. The manager approves or declines each one. Everyone can see which
routes are open, which have been requested, and who has the taken ones.

**Live site:** https://sccol-weekend-routes.vercel.app
**Manager tools:** https://sccol-weekend-routes.vercel.app/#manager (needs the manager passcode)

## For drivers

1. Type your name once. Your phone remembers it.
2. Tap every open route and date you want. A bar at the bottom shows what you picked.
3. Press **Send requests**.
4. Check back under **Your requests** to see whether each one was approved.

A route someone else has requested can still be requested. The manager picks who gets it.
To cancel a request, tell the manager.

**Email (optional):** add your email next to your name to hear when a request is approved,
declined or released. Tick "Email me a reminder" to also get an email the evening before
(around 5 PM) each route you get. Your email never shows on the board.

## For the manager

- **Waiting for approval** lists requests in the order they came in. Approving one person
  declines everyone else who asked for that route and date.
- **Assigned** lists who has each route. **Release** puts a route back to open.
- **Assign a route** gives a route straight to someone who asked in person or by text.
- **Dates**: open new Saturdays and Sundays when the next month is posted, or close a date.
- **Routes**: add a route (for example `SCCOL26`, Saturday) with optional details: start time,
  where to report, area covered, notes, and up to 8 details of your own (like "Vehicle: Van 12").
  **Edit** changes an existing route's details. A route can't move to the other day while it
  has open requests. **Retire** takes a route off the board. Drivers see the start time and area
  under each route, and everything else in the **Route details** section of the board.
- **Passcode**: change the manager passcode.
- **Email**: set the address that gets new-request alerts, paste the Gmail sender link, send a
  test email, and see the last few emails and whether they went out. Several requests sent
  together arrive as one alert.

## Email setup (one time)

Emails are sent from the site owner's Gmail by a small Google Apps Script, `mailer/Code.gs`.
Free Gmail allows about 100 emails a day.

1. Go to https://script.google.com and click **New project**. Paste in `mailer/Code.gs`, then
   put the sender key on the `KEY` line. The key is in the database
   (`private.mail_settings.mailer_token`), not in this repo.
2. Click **Deploy > New deployment**, choose **Web app**, and set **Execute as: Me** and
   **Who has access: Anyone**. Click **Deploy** and authorize it.
3. Copy the Web app URL (it ends in `/exec`). On the manager page, paste it under **Email >
   Gmail sender link** and click **Save link**.
4. Enter the alert address, click **Save**, then click **Send a test email**.

If you edit the script later, use **Deploy > Manage deployments > Edit > New version** so the
link stays the same.

## How it is built

- `web/index.html` is the whole site: one static page with no build step. It is hosted on Vercel
  (project `sccol-weekend-routes`).
- `supabase/` holds the database. It is a Supabase project called `weekend-routes`, on the free
  tier, in us-east-1.
  - `001_schema.sql`: the tables live in a `private` schema that the public API can't reach.
    The page only calls the functions in `public`.
    - Anyone can call `get_board` and `submit_request`.
    - Every other function checks the manager passcode first. The passcode is stored as a
      bcrypt hash.
    - Ten wrong passcode guesses from one source lock that source out for 15 minutes.
    - Nothing is ever erased: closed dates and retired routes are hidden instead.
  - `002_seed_december_2026.sql`: the December 2026 weekends and routes.
  - `003_email.sql`: email.
    - Drivers' addresses go in `private.request_contacts` and are never returned to the page.
    - `flush_notifications()` sends what's due: the supervisor alert, approval notices and
      reminders. The page calls it after each batch of requests and after each manager action.
    - Emails are handed to the Gmail script with `pg_net`.
  - `004_email_schedule.sql`: an hourly `pg_cron` job, at 7 minutes past the hour. It sends the
    evening-before reminders (5 PM Eastern on) and catches anything the page missed.
  - `005_route_details.sql`: route details (`private.route_details`) and `save_route()`, which
    adds a route or edits one.
- `mailer/Code.gs`: the Gmail sender (Google Apps Script web app).

The manager passcode and the email sender key are not stored in this repository.

### Redeploying the page

Create a new production deployment of the `sccol-weekend-routes` Vercel project from this
branch, with the root directory set to `weekend-routes/web`. You can also run
`vercel deploy --prod` from `web/`.
