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

## For the manager

- **Waiting for approval** lists requests in the order they came in. Approving one person
  declines everyone else who asked for that route and date.
- **Assigned** lists who has each route. **Release** puts a route back to open.
- **Assign a route** gives a route straight to someone who asked in person or by text.
- **Dates**: open new Saturdays and Sundays when the next month is posted, or close a date.
- **Routes**: add a route (for example `SCCOL26`, Saturday) or retire one.
- **Passcode**: change the manager passcode.

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

The manager passcode is not stored in this repository.

### Redeploying the page

Upload `web/index.html` as a new production deployment of the `sccol-weekend-routes` Vercel
project, either with `vercel deploy --prod` from `web/` or through the Vercel dashboard.
