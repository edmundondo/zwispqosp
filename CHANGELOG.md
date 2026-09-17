# Changelog

All notable changes to the Matokipedo privileged admin backend are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/) (MAJOR.MINOR.PATCH).

The version number shown here matches the `<meta name="app-version">` tag in `index.html` and the
`v{version}` badge in the page's footer.

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
