# Changelog

All notable changes to the Matokipedo privileged admin backend are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/) (MAJOR.MINOR.PATCH).

The version number shown here matches the `<meta name="app-version">` tag in `index.html` and the
`v{version}` badge in the page's footer.

## [0.8.0] — 2026-09-23

### Added
- Raw CSV export can now download **`customers`** (follow-up phone numbers, E.164) and
  **`customer_emails`** (follow-up emails) for the selected site.

### Fixed
- CSV export neutralises spreadsheet formula injection in visitor-typed text (cells starting with
  `=`, `+`, `-`, `@`), while leaving `+263…`-style phone numbers readable.

## [0.7.0] — 2026-09-23

### Added
- **Pipeline health card on Overview.** Per table, for the selected site: when the last real
  public submission arrived, counts for the last 24h / 7 days, and distinct devices (7d), with a
  🟢/🟡/🔴/⚪ freshness flag. Added because a silent backend rejection (below) looked exactly like
  "no testers yet" on this dashboard.
- `supabase-antispam-migration.sql` — the exact SQL of that migration, kept here (this repo holds the project's shared migrations).

### Fixed
- A panel whose backend fetch failed (e.g. an expired login → `JWT expired`) stayed on
  "Loading…" forever because the error was only logged to the console. It now shows the real
  error in the panel, with a sign-in-again hint for auth errors.
- Root cause of missing tester results, fixed in the shared database (migration
  `add_device_id_antispam_and_open_lang_codes`): the public sites send a `device_id` column that
  didn't exist, so every public insert was rejected. Also opened `translations.lang` to any
  2–4 letter code and added the per-device rate-limit trigger the demo sites' comments promised.

## [0.6.1] — 2026-09-18

### Added
- Malawi (`mw`) added to `SITE_LABELS`, `MISSING_LANGS` and `PROVIDER_DIRECTORY` — the site
  selector now includes Malawi alongside Zimbabwe, Botswana, South Africa, Zambia and Mozambique.
  `PROVIDER_DIRECTORY.mw` covers Airtel Malawi, TNM (Telekom Networks Malawi), Malawi
  Telecommunications Limited (MTL) and Starlink — see `maispqosd`'s CHANGELOG for the sourcing
  detail behind each figure. `MISSING_LANGS.mw` lists the eight Malawian languages still shipping
  with empty `I18N` content on the public demo (Chitumbuka, Chiyao, Chilomwe, Chisena, Chitonga,
  Chingoni, Chilambya, Chinyakyusa) — Chichewa isn't in this list since it already has real
  best-effort draft content.
- This same change was applied in lockstep to `bwispqosp`, `saispqosp`, `zaispqosp` and
  `moispqosp`, plus the new `maispqosp` repo (first build, v0.1.0), so every admin panel's site
  list stays in sync per the established template procedure.

## [0.6.0] — 2026-09-17

### Added
- **Role-based access control (RBAC) for the admin panel.** `admins.role` is now one of `viewer`
  (read-only — the default for any newly-added admin), `country_admin` (read/write, scoped to the
  country/site codes in `admins.scope`), or `global_admin` (full read/write across every country,
  but only while break-glass is switched on). A "Global Admin · break-glass ON/OFF" badge now sits
  next to "Signed in as…" in the header, with a toggle button for eligible global admins. Every
  activation/deactivation calls a new `toggle_break_glass()` Postgres RPC — the only way that flag
  can change — and writes a row to a new `admin_audit_log` table each time, so elevation is never
  silent or standing-by-default. The four write actions (moderation delete, ISP-license save,
  translation approve/reject) now check `canWrite(site)` client-side first; the real enforcement
  is server-side RLS via new `has_write_access(site)` / `is_global_admin()` Postgres functions,
  gating UPDATE/DELETE on every report table and on `provider_licenses`.
- This closes a real gap: every admin row previously had unrestricted global read/write/delete
  with zero per-country scoping, since `is_admin()` only ever checked "does this uid have *any*
  row in `admins`" — read was already public on every table regardless, so the actual boundary
  being fixed here is write/delete, not visibility.

### Fixed
- **The site-selector dropdown/header only ever showed a country once that country had at least
  one row in `qos_reports`**, so a freshly-launched country's own site never appeared as an
  `<option>` at all and the dropdown rendered visibly blank. `populateSiteSelect()` now always
  seeds every country from `SITE_LABELS` up front (all five are already known there), then adds
  any others found live — every deployed copy now shows its own country correctly from first
  load, with or without report data yet.

## [0.5.1] — 2026-09-17

### Changed
- **Full benchmark report is now shown inline, as the leaf of the same breadcrumb Explorer used
  everywhere else, instead of opening in a new tab/window.** Ed's own framing: the drill-down
  should be "auto-scrollable inline... NOT a new tab." Drilling Connection type → ISP now renders
  the full report (stat grid, 12-week QoS trend, complaint-cluster keyword tally, and a scrollable
  raw-comments table) directly inside the Benchmark reports card; the breadcrumb trail still lets
  you come back out to the ISP list or the connection-type list at any point, same as every other
  panel.
- The report's **Print / Save as PDF** button still produces a real, printable PDF, but now via a
  scoped in-page print (a new `printElementById()` helper hides everything else on the page for the
  duration of the print, then restores it once the browser's print dialog closes) rather than
  opening a second document in a new tab to print from.

## [0.5.0] — 2026-09-16

### Added
- **A single, condensed, breadcrumb-navigable Drill-down Explorer, replacing five different
  layouts that each required scrolling through a stack of separate cards to see everything.**
  Ed's own framing: "I just need a proper drill down sense and you can always come out ... for
  example, Harare, you end up naming the towns in Harare, and those areas break down further." —
  every panel below now works this way, condensed into one card per tab with its own internal
  scroll, not a page you scroll up and down through:
  - **Provider analytics** — City → Area/suburb (real, sourced areas — see `zwispqosd` v1.3.0 —
    with an explicit "All of `<city>`" and "No area given" bucket for reports that predate this
    field or skipped it) → ISP → that ISP's QoS/reliability/speed/net-conversion numbers plus the
    individual reports behind them ("last unit"), replacing the six stacked filter/bar/table cards
    from v0.4.0.
  - **ISP licensing** — Status → ISP → the full record (contact, fee, renewal, notes), with an
    "Edit this record ↑" button that loads it straight into the add/update form.
  - **Benchmark reports** — Connection type (Mobile / Fixed-Wireless / Other-unlisted, from
    `PROVIDER_DIRECTORY`) → ISP → opens the full report (still a standalone printable document in
    a new tab, not squeezed into the card).
  - **Moderation** — for the four tables with a real geography (`qos_reports`, `status_reports`,
    `speed_reports`, `conversions`): City → Area → ISP → the actual deletable rows. The other
    three tables (`referral_clicks`, `tester_feedback`, `translations`) have no comparable
    geography to drill through, so they deliberately keep the flat table rather than a fake
    hierarchy.
  - **Translations** — Language → that language's suggestion queue (approve/reject), instead of
    every language's table rendered at once.
  - **Export is unchanged on purpose** — Ed was explicit that this tab should stay a
    non-interactive report-picker, not a drill-down.
- **Every Overview stat tile is now a clickable entry point** into the relevant drill-down instead
  of a static number: QoS ratings/status reports/speed tests/switch-signup events/net conversions
  jump to Provider analytics; referral clicks and tester feedback (no real ISP/geography to drill
  through) jump to Moderation's flat table for that data; translations-pending jumps to the
  Translations tab.
- Every breadcrumb trail is clickable at every level — "always come out" — and switching the site
  selector resets every tab's drill-down path so a breadcrumb from one country's data never gets
  stranded showing another's empty state.

### Notes
- Companion to `zwispqosd` v1.3.0, which adds the real area/suburb picker these panels now surface.
- Not yet ported to `bwispqosp`/`saispqosp`/`zaispqosp`/`moispqosp` — same shared codebase and
  Supabase tables, so the identical change should land in all four eventually, but they have no
  live tester data yet to drill into.

## [0.4.1] — 2026-09-16

### Fixed
- Defensively applied the same `escAttr()` fix from v0.4.0 to `deleteModRow`/`approveTranslation`/
  `rejectTranslation`'s `onclick` handlers, which pass a row `id` the same
  `JSON.stringify()`-in-a-double-quoted-attribute way. These happen to be safe today (`qos_reports`
  and `translations` both use an `int8` id per SCHEMA.md, and `JSON.stringify()` doesn't quote
  numbers) — but SCHEMA.md doesn't confirm the `id` type for every report table individually, and
  the fix is free, so it's applied everywhere this call pattern occurs rather than left as a latent
  risk if a table's `id` ever turns out to be a UUID/string.

## [0.4.0] — 2026-09-16

### Added
- **Provider analytics is now a real drill-down, not just national averages.** A new filter row
  lets you narrow every panel to one city/region and/or a time window (7/30/90 days/all time), and
  every bar — a city, an ISP — is clickable to drill straight into it, cascading: click a city in
  "Reports by city / region" to scope everything below to it, then click an ISP bar to scope
  further.
- New **"Reports by city / region"** card: raw report counts (QoS + status + speed combined) per
  city, independent of any ISP filter — the fastest way to confirm testers in a given region are
  actually getting reports through, before looking at any ISP-level number.
- New **"Individual reports — last unit"** table: the literal underlying submissions behind every
  average above — timestamp, ISP, city, the rating/status/speed value, connection/device detail
  when a speed test carries it (connection type, device type, latency, jitter, packet loss), and
  the tester's own comment. Newest first, filtered the same way as everything else on the tab,
  capped to the latest 500 with a pointer to Raw CSV export for the rest.
- Every bar in Provider analytics now shows its sample size (n) next to the value, so a 5★ average
  from one report isn't read the same as a 5★ average from fifty.

### Fixed
- **Inline `onclick` handlers that pass a string argument via `JSON.stringify()` were silently
  broken** whenever that string contained no quotes of its own but was embedded inside a
  double-quoted HTML attribute — `onclick="fn(${JSON.stringify(str)})"` renders as
  `onclick="fn("Some Value")"`, and the HTML parser closes the attribute at the first embedded
  quote, mangling everything after it. Found live in the Benchmark reports tab's provider-picker
  buttons (`openFullReport`) while building the drill-down above (which needed the same
  string-argument pattern for its clickable bars). Added an `escAttr()` helper that HTML-entity-
  escapes the `JSON.stringify()` output before embedding it, and applied it everywhere this
  pattern is used, including the new drill-down's bars and filter pill.
- Footer version badge said v0.3.3 while `<meta name="app-version">` already read 0.3.4 — both now
  read v0.4.0.

### Notes
- Triggered by Ed's own framing: "I got some testers in the respective regions testing but I don't
  see the results" — the underlying reports already carried a `city` (and, for speed tests that
  ran the richer migration, connection/device/latency/jitter/packet-loss detail too), but this app
  had never surfaced any of it below a single national-average bar per ISP. This change reaches
  all the way down to the individual submitted report, not just a new aggregate cut.
- Not yet ported to `bwispqosp`/`saispqosp` — same multi-tenant app, so the identical change should
  land in both to avoid drift (see the `matokipedo-isp-tracker-qc` skill's parity-audit practice),
  but Botswana/South Africa have no live tester data yet to drill into.

## [0.3.3] — 2026-09-10

### Fixed
- **Bug audit, triggered by the Botswana/South Africa language rollout**: the Translations
  panel's "still-missing languages" note was a single hardcoded, Zimbabwe-only sentence — wrong
  for Botswana and South Africa (which have their own, different, blank-language lists as of
  bwispqosd/saispqosd v1.1.0), and *also factually wrong for Zimbabwe itself*: it listed TjiKalanga
  and Tonga as still needing translation, but both already carry full draft content in
  `zwispqosd`'s `I18N` object (confirmed by loading and inspecting the object directly, not by
  trusting the old note). Replaced with a `MISSING_LANGS` map per site, checked against each
  demo's actual `I18N` content, and a `renderMissingLangNote()` function that renders the correct
  note for whichever site is selected. Zimbabwe's real list is four languages (Chibarwe,
  Khoisan/Tjwao, Nambya, Ndau), not six.
- Removed a dead, always-true conditional in the raw CSV export (`if(table !== "provider_licenses"
  || true) ...`) that made it look like `provider_licenses` might skip the site filter — it never
  did (the `|| true` made the condition unconditionally true), but the code was confusing and
  looked like a bug. Now just always scopes by `site`, matching the actual (and correct) behavior.
- Corrected two stale claims in SETUP.md: "Overview — cross-site totals" and "Moderation — across
  all sites at once" both overstated what the app does — every panel is scoped to the selected
  site via `currentSite`, not aggregated across sites. Also updated the stale "PROVIDER_DIRECTORY,
  zw only so far" note now that all three sites are populated.

### Notes
- This was a routine audit-for-parity pass across `zwispqosp`/`bwispqosp`/`saispqosp` (prompted by
  "audit for bugs, functionality then update bwispqosp/saispqosp to match zwispqosp") — the three
  admin app copies were already byte-identical in their JS/HTML aside from title/version/
  `currentSite` default before this fix, and stay that way after it. No functional drift was found
  between the three copies; the bugs found here were pre-existing in the shared template and are
  now fixed in all three at once.

## [0.3.2] — 2026-09-10

### Added
- **`PROVIDER_DIRECTORY.bw` and `.za` populated** — Botswana (Orange Botswana, Mascom
  Wireless, BTC Mobile/BeMobile, Starlink, Independent ISPs) sourced from BOCRA's 2024
  Annual Report and operators' own results; South Africa (Vodacom, MTN South Africa,
  Telkom Mobile, Cell C, rain, Openserve, Vumatel, Herotel, MetroFibre Networx,
  Frogfoot Networks) sourced from ICASA's State of the ICT Sector Report and each
  company's own investor/trading results. Both sites' formatted exports (PDF/CSV/EPUB)
  now work here the same way Zimbabwe's already did — no code changes needed beyond
  the data itself.
- Two new sibling deployments of this same admin app now exist: **bwispqosp**
  (`currentSite` defaults to `"bw"`) and **saispqosp** (defaults to `"za"`) — see the
  `qos` skill's replication template. All three copies share one Supabase project
  and stay in sync by hand, same as `PROVIDER_DIRECTORY` always has.

### Notes
- The public demo counterparts are **bwispqosd** and **saispqosd** (siblings of
  zwispqosd), both English-only v1 releases with no export options, no Cloudflare
  Radar national benchmark, and empty `ISP_ASN`/`PHONE_ISP_PREFIXES` — see each
  repo's own README/CHANGELOG for the full list of deliberate scope cuts.

## [0.3.1] — 2026-09-10

### Changed
- **Footer now matches `zwispqosd`'s branding** — copied the Matokipedo logo + "Live
  infrastructure monitoring by Matokipedo" tagline treatment over verbatim (same markup, same
  `.matokipedo-footer`/`.matokipedo-brand`/`.matokipedo-logo`/`.matokipedo-tagline` CSS classes),
  with this app's own admin-specific line kept underneath. Added `matokipedo-logo.jpg` to this
  repo (copied from `zwispqosd`, verified with `file` — genuine JPEG, not the HEIC-mislabeled
  trap noted in the maintenance skill) since it wasn't here before.

### Notes
- This is now a third piece of brand/data duplicated by hand across the two repos, alongside
  `PROVIDER_DIRECTORY` (v0.3.0). Keep the logo and footer markup in sync if either changes on the
  public demo.

## [0.3.0] — 2026-09-10

### Added
- **All six export options moved here from the public `zwispqosd` demo**: Export PDF Report,
  Export ISP CSV, Export QoS CSV, Export Status CSV, Export Speed CSV, and Export EPUB. They live
  in a new "Formatted reports" card at the top of the Export tab, above the existing raw
  per-table CSV export (now labelled "Raw CSV export" to tell the two apart).
- These are rebuilt against Supabase's full history for the selected site (via the same
  `fetchAll()` used elsewhere in this app), not the public demo's client-side cache capped at
  1000 rows — so they're strictly more complete than what the demo used to offer, and they work
  for whichever site is selected, not just Zimbabwe.
- Added `PROVIDER_DIRECTORY`, a duplicate of `zwispqosd`'s hardcoded provider list (name, type,
  subscriber counts, sourcing) — needed because Supabase itself only has the report tables, not a
  `providers` table. Only `zw` is populated for now; the ISP CSV/EPUB/PDF Report buttons show a
  clear message instead of exporting garbage if a site (bw, za) has no directory entry yet.
- Added the JSZip CDN script tag (same free, open-source MIT library `zwispqosd` used) for the
  EPUB export.

### Changed
- One simplification versus the original: the public demo's "Down 24h+" styling comes from an
  unbroken streak of "down" reports *per city*; the moved-here version computes it per ISP across
  all cities (`latestStatusFor`). Close enough for a report a human reads once; flag it if you
  want the exact per-city version ported too.

### Notes
- `PROVIDER_DIRECTORY` has to be kept in sync by hand with `zwispqosd/index.html`'s `DATA` array
  until providers move into a real Supabase table (tracked in SETUP.md's "What's deliberately NOT
  in this v1").

## [0.2.0] — 2026-09-09

### Added
- Google sign-in and native passkey (WebAuthn) support on the login screen, alongside the
  v0.1.0 email/password baseline.

## [0.1.0] — 2026-09-09

### Added
- First build: Overview, Provider analytics, ISP licensing CRM, full/paid benchmark reports,
  Moderation, Translations review queue, and CSV export — gated by Supabase Auth + RLS via an
  `is_admin()` function, not a hardcoded service-role key. See SETUP.md.
