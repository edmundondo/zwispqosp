# Changelog

All notable changes to the Matokipedo privileged admin backend are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/) (MAJOR.MINOR.PATCH).

The version number shown here matches the `<meta name="app-version">` tag in `index.html` and the
`v{version}` badge in the page's footer.

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
