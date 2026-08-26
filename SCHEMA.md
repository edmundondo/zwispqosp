# zwispqos Supabase Schema

**Project:** `zispqos` (AWS, us-east-2, Free tier)
**Consumed by:** `zwispqosd` (public, live at edmundondo.github.io/zwispqosd)
**Documented:** 2026-08-25

This file exists because the schema itself lives only inside Supabase's UI —
nothing describing it was ever committed to a repo. This is the paper trail.

---

## Multi-tenancy: the `site` column

**Discovered after initial documentation, confirmed via live browser Network tab:** this
project is very likely a **shared backend across the whole Matokipedo country-tracker
family**, not a Zimbabwe-only project. Evidence:

- The Supabase project itself is named generically `zispqos` — not `zwispqos` or
  anything Zimbabwe-specific.
- Multiple tables (`translations`, `qos_reports`, and likely others) have a `site` text
  column.
- The live Zimbabwe site's actual outgoing requests filter by it, e.g.:
  ```
  qos_reports?select=isp,stars,city,comment,created_at&site=eq.zw&order=created_at.desc&limit=1000
  ```

**What this means in practice:** `site` is the tenant discriminator. `'zw'` = Zimbabwe.
Onboarding a new country (Botswana, or relaunching South Africa) very likely means
reusing this exact project and these exact tables — just inserting/selecting with that
country's own `site` code — rather than creating a second Supabase project from scratch.

**Not yet confirmed:**
- Whether rows for any other `site` value already exist in these tables (e.g. from an
  earlier South Africa integration attempt).
- The exact place in `index.html`'s JS where `site` gets attached to outgoing
  insert/select calls (not fully visible in every code excerpt reviewed so far — read the
  live file directly to confirm the mechanism before replicating it for a new country).
- Whether `customers` and `tester_feedback` also carry a `site` column (not confirmed
  either way — check before assuming).

**Operational consequence:** because this project's anon key is shared, rotating it
(e.g. after an exposure) affects every country's live site simultaneously, not just one.
Before ever rotating this key again, confirm every site currently using it and update all
of them together, or the others will silently flip from 🟢 to 🔴.

---

## Tables

### `qos_reports`
Crowdsourced quality-of-service ratings per ISP. Powers the star ratings shown
on the live site.

| Column | Type | Notes |
|---|---|---|
| id | int8 | PK |
| site | text | |
| isp | text | |
| stars | int? | *(not fully confirmed — verify in Table Editor)* |
| city | text | *(used in `submitReport()`)* |
| comment | text | |
| created_at | timestamptz | |

**RLS:** ✅ Enabled
- `Public can add a sane report` — INSERT, public
- `Public can read reports` — SELECT, public

---

### `customers`
Phone numbers collected for follow-up / re-contact. **The one table with no
public SELECT — correctly locked down.**

| Column | Type | Notes |
|---|---|---|
| phone_number | text | PK (key icon in Table Editor) |
| country | text | |
| detected_isp | text | |
| first_seen | timestamptz | |
| last_seen | timestamptz | |

**RLS:** ✅ Enabled
- `Public can add a contact record` — INSERT, public
- `Public can refresh their own contact record` — UPDATE, public
- **No SELECT policy** — table is not publicly readable. This is intentional
  and correct; do not add a public SELECT policy to this table.

⚠️ Not queried in `initBackend()` — by design, this table is write-only from
the client's perspective.

---

### `conversions`
"I switched or signed up" reports — proof-of-impact data shown as a badge on
the live site.

| Column | Type | Notes |
|---|---|---|
| to_isp | text | from `submitConversion()` |
| from_isp | text | |
| reasons | text[] or jsonb? | *(verify — passed as array in code)* |
| city | text | |
| comment | text | |
| created_at | timestamptz | |
| *(2 more columns — 8 total per Table Editor, not yet confirmed)* | | |

**RLS:** ✅ Enabled
- `Public can add a sane conversion` — INSERT, public
- `Public can read conversions` — SELECT, public

---

### `referral_clicks`
Tracks outbound clicks to ISP signup links.

| Column | Type | Notes |
|---|---|---|
| isp | text | |
| context | text | e.g. `"detail"` (default in code) |
| created_at | timestamptz | |
| *(2 more columns — 5 total, not yet confirmed)* | | |

**RLS:** ✅ Enabled
- `Public can log a sane referral click` — INSERT, public
- `Public can read referral click counts` — SELECT, public

---

### `speed_reports`
Crowdsourced bandwidth tests. Powers the ranked speed table (30-min
rolling-window averaged).

| Column | Type | Notes |
|---|---|---|
| isp | text | |
| city | text | |
| download_mbps | numeric | |
| upload_mbps | numeric | |
| comment | text | |
| created_at | timestamptz | |
| *(11 more columns — 17 total, not yet confirmed. Largest table by column count — worth a full audit.)* | | |

**RLS:** ✅ Enabled
- `Public can add a sane speed report` — INSERT, public
- `Public can read speed reports` — SELECT, public

---

### `status_reports`
Live/Partial/Down status per ISP per city.

| Column | Type | Notes |
|---|---|---|
| isp | text | |
| city | text | |
| status | text | e.g. "Live" / "Partial" / "Down" |
| comment | text | |
| created_at | timestamptz | |
| *(2 more columns — 7 total, not yet confirmed)* | | |

**RLS:** ✅ Enabled
- `Public can add a sane status report` — INSERT, public
- `Public can read status reports` — SELECT, public

---

### `tester_feedback`
General feedback / "help us improve" submissions (location, language, UX
feedback).

| Column | Type | Notes |
|---|---|---|
| *(8 columns total — none confirmed yet; not referenced in the client JS we've read so far)* | | |

**RLS:** ✅ Enabled
- `Public can submit feedback` — INSERT, public
- `Public can read feedback` — SELECT, public

⚠️ Not queried in `initBackend()`. Confirm whether this is meant to surface
anywhere on the live site, or is intentionally a write-only inbox for manual
review in the Supabase dashboard.

---

### `translations`
Community-submitted UI translation suggestions (ChiShona, IsiNdebele,
TjiKalanga). Auto-promotes to "approved" after 2 endorsements.

| Column | Type | Notes |
|---|---|---|
| id | int8 | PK |
| site | text | |
| lang | text | e.g. "sn", "nd", "kck" |
| string_key | text | |
| suggested_text | text | |
| source_note | text | |
| endorsements | int | |
| status | text | "pending" / "approved" |
| created_at | timestamptz | |

**RLS:** ✅ Enabled
- `Public can read translations` — SELECT, public
- `Public can suggest a translation` — INSERT, public

---

## Connection config (client-side, `index.html`)

```js
const SUPABASE_CONFIG = {
  url: "<project URL — Settings → API>",
  anonKey: "<anon/publishable key — Settings → API>"
};
```

This is the **anon/publishable** key, safe for client-side exposure by
Supabase's design — its safety depends entirely on the RLS policies above
being correct, not on the key being secret.

**Never commit the actual key value to `zwispqosp` either.** Even in a
private repo, treat it as environment config: reference where it lives
(Supabase dashboard → Settings → API), not the literal string. If you want
it in a file for your own reference, put it in a `.env` file and add `.env`
to `.gitignore` before the first commit.

---

## Known gaps / follow-ups

- [ ] Confirm whether `site` values other than `'zw'` already exist in any table —
      check before assuming Botswana/South Africa would be starting from zero rows.
- [ ] Confirm `customers` and `tester_feedback` do/don't have a `site` column too.
- [ ] Find and document the exact code path in `index.html` that sets `site` on
      outgoing requests.
- [ ] Confirm exact column types for `conversions`, `referral_clicks`,
      `speed_reports` (largest table, 17 cols), and `status_reports` — only
      partially known from client code, not from Table Editor directly.
- [ ] Fully document `tester_feedback` columns — none confirmed yet.
- [ ] Confirm the `UPDATE` policy on `customers` restricts by matching
      `phone_number` in the request (not just "any public update").
- [ ] Consider whether `conversions.reasons` is `text[]` or `jsonb` — affects
      how it should be queried/exported later.
- [ ] Confirm whether the `schema.sql` file referenced in `index.html`'s own code
      comments actually exists in `zwispqosd` — it wasn't in the file list as of
      this session.
