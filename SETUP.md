# zwispqosp — privileged admin backend: setup

**Status as of 2026-09-09:** `index.html` (v0.2.0, Google sign-in + passkeys included) is already
committed to this repo and live via GitHub Pages — step 4 below is done. This file and the
migration SQL are being added now so the rest of the setup (steps 1-3) isn't only documented in
chat history. If you've already run the migration and created your admin login, skip to whichever
section you haven't done yet.

**v0.2.0 update:** added Google sign-in and native passkey (WebAuthn) support to the login
screen, on top of the v0.1.0 email/password baseline. Section 3 below is new — read it before
using Google/passkey sign-in, it needs dashboard steps only you can do.

This is a first build against the concept you described (public demo with shared access vs. a
private, privileged backend for analytics/reporting/tweaking), built once I found that
`zwispqosd`'s own code already half-implements the business model: it ships a **free sample ISP
benchmark report** whose own call-to-action says *"A licensed subscription gets [ISP] a monthly
refreshed report, historical trend charts, raw anonymized comment access, and priority flagging
of emerging complaint clusters."* This admin app is the other half — the tool that actually
delivers on that pitch, plus day-to-day ops for you.

I could not test any of this against your real Supabase project or create a real admin login —
this session only has the public anon key (already visible in `zwispqosd`'s own
`index.html`), no dashboard or service-role access. Everything below is written from reading that
existing code's schema carefully, then verified for JS syntax and layout in a local, offline
sandbox (Supabase's own script couldn't load there — no outbound network — so the graceful
"library didn't load" fallback path is what got tested, not a real sign-in). Treat this as a
solid first pass to review and test for real, not a finished, live-verified product.

## 1. Run the migration

Open your Supabase project (`etdxreehedewcctkdvuo`, the same one `zwispqosd` already talks to) →
SQL Editor → paste and run `supabase_admin_migration.sql`. It's additive: new tables
(`admins`, `provider_licenses`) plus new admin-only policies alongside the existing public
policies — it does not touch or narrow anything the live public site depends on.

**Assumption worth checking first:** the migration assumes every existing table
(`qos_reports`, `status_reports`, `speed_reports`, `conversions`, `translations`,
`referral_clicks`, `tester_feedback`) has a Supabase-default `id` primary key column, since the
admin app's moderation/delete and translation-approval features key off `id`. That's the standard
default when a table is created via the Supabase UI, but I couldn't confirm it without database
access — if a table lacks one, that table's delete/update in the admin app will error, and the
fix is either adding an `id bigint generated always as identity primary key` column, or telling
me the actual key column so I can adjust the queries.

## 2. Create your admin login

Authentication → Users → Add user → your email + a password. Copy the new user's UUID, then in
the SQL Editor:

```sql
insert into admins (user_id, email) values ('<uuid-here>', 'your@email.com');
```

Without this row, signing in works but every admin query is denied by RLS (by design).

## 3. Turn on Google sign-in and passkeys

Both need one-time dashboard/console setup I can't do from here (no dashboard access) — this is
the part that actually needs you:

**Google (the "SSO" you asked for — see note below on what that means here):**
1. Google Cloud Console → create an OAuth 2.0 Client ID (type: Web application). Authorized
   redirect URI: `https://etdxreehedewcctkdvuo.supabase.co/auth/v1/callback`.
2. Supabase dashboard → Authentication → Providers → Google → paste the Client ID and Client
   Secret from step 1, enable it.
3. Supabase dashboard → Authentication → Settings → make sure **manual linking** is allowed (it's
   what lets `linkIdentity()` attach Google to an account that already exists) — the setting name
   varies by dashboard version; if you can't find it, search the page for "linking."

**Passkeys (beta, native to Supabase Auth):**
1. Supabase dashboard → Authentication → Passkeys (or under Providers/WebAuthn, naming may vary
   since this is beta) → set the Relying Party ID to the exact domain this file will be served
   from (e.g. `edmundondo.github.io` if it stays under GitHub Pages) and add that origin.
   **Changing this later breaks every passkey already registered** — get the domain right first.
2. Nothing else to configure; `index.html` already calls the right APIs.

**First-login order matters:** a brand-new "Sign in with Google" click on a browser with no
existing session creates a *new*, separate Supabase user — one that isn't in your `admins` table
yet, so it'll be denied. Same for passkeys — `registerPasskey()` requires an existing session.
So the very first time: sign in with the **password** account from step 2, then use the "Link
Google" / "🔐 Add a passkey" buttons that appear next to your email in the header. After that,
Google and the passkey both work as direct sign-in options from the login screen.

**What "SSO" means here:** you asked for SSO; real enterprise SSO (SAML) needs Supabase's Pro
plan ($25/mo+) and an identity provider you'd have to stand up yourself (Okta/Azure AD/Google
Workspace SAML) — overkill for a one-person admin tool, and it cuts against your own preference
for free tooling. What's built instead is Google OAuth sign-in, which is what most solo operators
mean by "SSO" in practice, at zero extra cost. If you later run this for a team and want real
SAML federation, say so and I'll add `supabase.auth.signInWithSSO({ domain: ... })` alongside
this — it's a straightforward addition once you actually have an identity provider to point it
at.

## 4. Publish the app

Same pattern as `zwispqosd`: put `index.html` in the `zwispqosp` repo, GitHub Pages
serves it. This file only ever holds the public anon key, never a service-role key — privilege
comes entirely from Supabase Auth + the RLS policies in step 1, not from the repo being secret.

**Worth knowing before you publish:** GitHub Pages only serves *private* repos on paid GitHub
plans (Pro/Team/Enterprise) — a private repo on a free account can't publish Pages at all. Since
this file's real protection is the login + RLS (not the repo's visibility — there's no secret in
the HTML to leak), making `zwispqosp` public wouldn't actually weaken anything; it would just be
discoverable if someone guessed the URL, same as `zwispqosd` already is. If you're on a free
GitHub plan, either make the repo public, or host this file somewhere that does serve private
repos (Netlify/Vercel/Cloudflare Pages all support that on their free tiers), or upgrade GitHub.

## What it does

- **Overview** — cross-site totals (ratings, status reports, speed tests, conversions, referral
  clicks, tester feedback, pending translations), reading full history, not the public site's
  client-side 1000-row cache.
- **Provider analytics** — QoS average, 30-day status reliability, average download speed, and
  net conversions per provider, computed live.
- **ISP licensing** — a small CRM: track each ISP as prospect → contacted → trial → active →
  lapsed/declined, with contact info, fee, and renewal date. This is the missing piece that turns
  "reach out to discuss" into an actual pipeline you can see.
- **Benchmark reports (full edition)** — the same report shape as the public teaser, plus what the
  teaser's CTA promises and the free version withholds: a 12-week trend chart, a best-effort
  keyword tally across comments (a rough stand-in for "complaint clustering" — good enough to spot
  a pattern, not a real NLP pipeline), and the raw anonymized comments themselves.
- **Moderation** — browse and delete recent rows in any of the report tables, across all sites at
  once if you want.
- **Translations** — every crowd-submitted translation suggestion, grouped by language, with
  approve/reject. This is also where the six still-missing Lite-page languages (TjiKalanga,
  Chibarwe, Khoisan/Tjwao, Nambya, Ndau, Tonga) would surface once someone submits something for
  them — the CHANGELOG in `zwispqosd` flagged those as skipped rather than guessed at.
- **Export** — CSV of any table, filtered to the selected site.

## What's deliberately NOT in this v1

- **Providers are still hardcoded** in `index.html`'s `const DATA = [...]` array on the public
  sites, not database-driven. Making the provider list itself editable from here (name,
  subscriber count, type) would mean also changing the public site to fetch from a `providers`
  table instead of its hardcoded array — a real, separate, more invasive change to a
  production file. I didn't make that call unilaterally; say the word and I'll design and build
  that migration path as its own reviewable step.
- **No email delivery.** "Monthly refreshed report" implies actually sending something on a
  schedule — this app only generates a report on demand when you click a provider. Automating
  that would need a scheduled job (a Supabase Edge Function on a cron trigger, most likely) and an
  email provider, which is a separate build.
- **Keyword tally, not real complaint clustering.** It's a plain stop-word-filtered word-frequency
  count over the free-text comments. It'll show you what's coming up a lot; it won't group
  "signal drops constantly" and "keeps disconnecting" as the same complaint.
