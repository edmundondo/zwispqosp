# tools/

## build_lite.py — Lite page generator (all six *ispqosd sites)

Generates the no-script `lite.html` + `lite-<lang>.html` pages for every demo site from each
site's own `index.html` (providers from `const DATA`, language list from the language chips,
version from `<meta name="app-version">`) and the Lite UI strings in `lite_strings.json`.

```
# from a folder that contains all six *ispqosd clones side by side
python3 zwispqosp/tools/build_lite.py .          # regenerate
python3 zwispqosp/tools/build_lite.py . --check  # exit 1 if any Lite page (or LITE_LANGS) is stale
```

Rules baked in:
- Providers are never hand-copied — edit `DATA` in `index.html`, bump the version, re-run.
- A Lite language page exists only where a Lite string set exists **and** it is the same standard
  language (see `LITE_REUSE`). Everything else in the chip row is shown greyed out.
- `sms: None` hides the SMS button — never ship a placeholder number.
- `index.html` must declare the same list in `const LITE_LANGS` (the `--check` run verifies it).
