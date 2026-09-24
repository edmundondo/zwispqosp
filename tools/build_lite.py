#!/usr/bin/env python3
"""
build_lite.py v2 (2026-09-23) — multilingual no-script Lite pages for all six *ispqosd sites.

Usage:
    python3 build_lite.py <dir-containing-the-six-*ispqosd-clones> [--check]

For every site it:
  1. reads <site>/index.html and extracts
       - `const DATA = [...]` (providers — never hand-copied),
       - the language chips (data-lang="xx">Label<) so the Lite language bar lists exactly the
         same languages, with the same labels, as the full site,
       - the app version (<meta name="app-version">) so lite and index always show one version;
  2. writes lite.html (English) + lite-<code>.html for every language that has a Lite string set
     in lite_strings.json AND is allow-listed for that site in LITE_REUSE below;
  3. everything else in the chip row is shown greyed out ("not yet translated for Lite").

Translation discipline (same as the full site): Lite strings are only reused across countries when
it is the SAME standard language (checked, not by name) — e.g. Zimbabwe's Chewa == Zambia's /
Mozambique's Cinyanja == Malawi's Chichewa (ISO 639-3 nya). South Africa's isiNdebele (nr) is NOT
Zimbabwe's IsiNdebele (nd) and never gets its strings. Lower-confidence reuse is flagged on-page.

--check: don't write, just report what would change (exit 1 if anything is stale).
"""
import html, json, re, sys, urllib.parse
from pathlib import Path

HERE = Path(__file__).resolve().parent
STRINGS = json.loads((HERE / "lite_strings.json").read_text(encoding="utf-8"))
RATING_EMAIL = "edmundondo@gmail.com"

# sms: None hides the SMS button (never ship a placeholder like +260XXXXXXXXX — a tappable
# link to a non-existent number looks like it worked and silently loses the rating).
SITES = {
  "zwispqosd": dict(site="zw", country="Zimbabwe", title="Zimbabwe ISP Tracker", regulator="POTRAZ",
                    eyebrow="POTRAZ · Zimbabwe Telecoms", sms="+263779687648",
                    source="data sourced from POTRAZ sector reports"),
  "bwispqosd": dict(site="bw", country="Botswana", title="Botswana ISP Tracker", regulator="BOCRA",
                    eyebrow="BOCRA · Botswana Telecoms", sms="+26776088884",
                    source="data sourced from BOCRA sector reports"),
  "saispqosd": dict(site="za", country="South Africa", title="South Africa ISP Tracker", regulator="ICASA",
                    eyebrow="ICASA · South African Telecoms", sms="+27750703948",
                    source="data sourced from ICASA sector reports and operator filings"),
  "zaispqosd": dict(site="zm", country="Zambia", title="Zambia ISP Tracker", regulator="ZICTA",
                    eyebrow="ZICTA · Zambia Telecoms", sms=None,
                    source="data sourced from ZICTA sector reports"),
  "moispqosd": dict(site="mz", country="Mozambique", title="Mozambique ISP Tracker", regulator="INCM",
                    eyebrow="INCM · Mozambique Telecoms", sms=None,
                    source="data sourced from INCM and operator reports"),
  "maispqosd": dict(site="mw", country="Malawi", title="Malawi ISP Tracker", regulator="MACRA",
                    eyebrow="MACRA · Malawi Telecoms", sms=None,
                    source="data sourced from company annual reports and MACRA licensing records"),
}

# site -> {chip code: (strings key, low_confidence_note or None)}
LITE_REUSE = {
  "zw": {c: (c, None) for c in ["sn", "nd", "ny", "st", "tn", "ve", "xh"]} | {
        "ts": ("ts", None)},
  "bw": {"tn": ("tn", None), "sn": ("sn", None), "nd": ("nd", None)},
  "za": {"xh": ("xh", None), "st": ("st", None), "tn": ("tn", None), "ve": ("ve", None),
         "ts": ("ts", "Reused from the Zimbabwe site's Shangani draft — a close variety of standard "
                      "South African Xitsonga, so lower confidence.")},
  "zm": {"ny": ("ny", None)},
  "mz": {"ny": ("ny", None), "pt": ("pt", None),
         "ts": ("ts", "Reused from the Zimbabwe site's Shangani draft — Xichangana is a close variety, "
                      "so lower confidence.")},
  "mw": {"ny": ("ny", None)},
}

FIELD_RE = {
    "name": re.compile(r'\bname:\s*"((?:[^"\\]|\\.)*)"'),
    "type": re.compile(r'\btype:\s*"((?:[^"\\]|\\.)*)"'),
    "subscribers": re.compile(r'\bsubscribers:\s*(null|-?\d+)'),
    "subLabel": re.compile(r'\bsubLabel:\s*"((?:[^"\\]|\\.)*)"'),
    "note": re.compile(r'\bnote:\s*"((?:[^"\\]|\\.)*)"'),
}

def unescape_js(s):
    return (s or "").replace('\\"', '"').replace("\\'", "'").replace("\\n", " ")

def extract_providers(text):
    m = re.search(r"const DATA\s*=\s*\[(.*?)\n\];", text, re.S)
    if not m:
        raise ValueError("const DATA = [...] not found")
    block, objs, depth, start, in_str = m.group(1), [], 0, None, None
    i = 0
    while i < len(block):
        ch = block[i]
        if in_str:
            if ch == "\\": i += 2; continue
            if ch == in_str: in_str = None
        elif ch in "\"'`": in_str = ch
        elif ch == "{":
            if depth == 0: start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                objs.append(block[start:i + 1]); start = None
        i += 1
    rows = []
    for o in objs:
        r = {k: (rx.search(o).group(1) if rx.search(o) else None) for k, rx in FIELD_RE.items()}
        if r["name"]: rows.append(r)
    return rows

def extract_chips(text):
    return [(c, html.unescape(l.strip())) for c, l in
            re.findall(r'<div class="chip lang-chip[^"]*" data-lang="([a-zA-Z-]+)">([^<]+)</div>', text)]

def sub_label(r):
    if r["subLabel"]: return unescape_js(r["subLabel"])
    if r["subscribers"] and r["subscribers"] != "null": return f"{int(r['subscribers']):,} subscribers"
    return "No public subscriber count"

CSS = """  body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;background:#0b0f14;color:#e8edf4;padding:20px 16px 60px;}
  .wrap{max-width:720px;margin:0 auto;}
  a{color:#7c9cff;}
  a:visited{color:#9c8cff;}
  .eyebrow{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#4fd1c5;font-weight:bold;margin-bottom:6px;}
  h1{font-size:24px;margin:0 0 6px;}
  p.sub{color:#8493a8;font-size:14px;margin-top:0;}
  .langbar{font-size:12px;color:#8493a8;margin:10px 0 4px;line-height:1.9;}
  .langbar strong{color:#e8edf4;}
  .langbar .off{color:#4a5568;}
  .notice{font-size:12px;color:#8493a8;background:#121821;border:1px solid #232c3a;border-radius:8px;padding:10px 12px;margin:14px 0 22px;}
  .draftnote{font-size:11px;color:#e8b93f;background:#201a08;border:1px solid #4a3a12;border-radius:8px;padding:8px 10px;margin:0 0 18px;}
  .provider{border-bottom:1px solid #232c3a;padding:14px 0;}
  .provider .name{font-weight:bold;font-size:15px;}
  .provider .meta{font-size:12px;color:#8493a8;margin-top:2px;}
  .provider .note{font-size:13px;margin-top:6px;overflow-wrap:anywhere;}
  .btn{display:inline-block;background:#161d28;border:1px solid #232c3a;border-radius:8px;padding:6px 10px;font-size:12px;color:#4fd1c5;text-decoration:none;margin-top:8px;margin-right:8px;}
  .btn.sms{color:#e8b93f;}
  footer{margin-top:30px;font-size:12px;color:#8493a8;}
  footer a{color:#8493a8;}
  .version{margin-top:6px;font-size:11px;color:#4a5568;}"""

def page_name(code): return "lite.html" if code == "en" else f"lite-{code}.html"

def render(cfg, version, providers, chips, lang, lite_langs):
    s = STRINGS[lang]; en = STRINGS["en"]
    labels = dict(chips)
    lang_label = labels.get(lang, "English" if lang == "en" else lang)
    full_href = "index.html" if lang == "en" else f"index.html?lang={lang}"
    # language bar: every chip on the full site, in the same order
    parts = []
    for code, label in chips:
        e = html.escape(label)
        if code == lang: parts.append(f"<strong>{e}</strong>")
        elif code in lite_langs: parts.append(f'<a href="{page_name(code)}" hreflang="{code}">{e}</a>')
        else: parts.append(f'<span class="off" title="Not yet translated for the Lite page — see the full site">{e}</span>')
    langbar = f'<div class="langbar">{s["lang_label"]}: ' + " &middot; ".join(parts) + "</div>"
    draft = ""
    if lang != "en":
        note = lite_langs[lang][1]
        draft = f'<div class="draftnote">{s["draftnote"]}' + (f"<br><span lang=\"en\">{html.escape(note)}</span>" if note else "") + "</div>"
    notice = s["notice"].replace('<a href="index.html">', f'<a href="{full_href}">')
    rows = []
    for r in providers:
        name = unescape_js(r["name"]); typ = unescape_js(r["type"])
        note = re.sub(r"<[^>]+>", "", unescape_js(r["note"]))
        subj = urllib.parse.quote(f"ISP Rating: {name} ({cfg['country']})")
        body = urllib.parse.quote(f"Provider: {name}\nScore (1-5): \nCity/town: \nComment: \n\n(sent from the {cfg['title']} Lite page, {lang_label})")
        btns = f'    <a class="btn" href="mailto:{RATING_EMAIL}?subject={subj}&amp;body={body}">{s["btn_email"]} &rarr;</a>\n'
        if cfg["sms"]:
            smsb = urllib.parse.quote(f"RATE {name} score: city: ")
            btns += f'    <a class="btn sms" href="sms:{cfg["sms"]}?&amp;body={smsb}">{s["btn_sms"]} &rarr;</a>\n'
        rows.append(f'''  <div class="provider">
    <div class="name">{html.escape(name)}</div>
    <div class="meta">{html.escape(typ)} &middot; {html.escape(sub_label(r))}</div>
    <div class="note">{html.escape(note)}</div>
{btns}  </div>
''')
    if cfg["sms"]:
        rate_p = s["rate_p"].replace("{sms}", cfg["sms"])
    else:
        rate_p = s.get("rate_p_nosms") or en["rate_p_nosms"]
        if "rate_p_nosms" not in s:  # no email-only translation exists — say so rather than guess one
            rate_p = f'<span lang="en">{rate_p}</span>'
    alternates = "\n".join(f'<link rel="alternate" hreflang="{c}" href="{page_name(c)}">' for c in ["en"] + list(lite_langs))
    return f"""<!DOCTYPE html>
<html lang="{lang}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="app-version" content="{version}">
<title>{cfg['title']} — Lite ({html.escape(lang_label)})</title>
<meta name="description" content="No-script lite version of the {cfg['title']}: {cfg['regulator']}-sourced provider list and a simple email{' or SMS' if cfg['sms'] else ''} quality rating, for slow connections and older phones.">
{alternates}
<!-- Generated by zwispqosp/tools/build_lite.py — edit providers in index.html / strings in lite_strings.json, then re-run. -->
<style>
{CSS}
</style>
</head>
<body>
<div class="wrap">
  <div class="eyebrow">{html.escape(cfg['eyebrow'])}</div>
  <h1>{cfg['title']} — Lite</h1>
  <p class="sub">{s['sub']}</p>
  {langbar}
  {draft}
  <div class="notice">
    {notice}
  </div>

  <h2 style="font-size:16px;">{s['providers_h2']}</h2>
{''.join(rows)}
  <h2 style="font-size:16px;">{s['rate_h2']}</h2>
  <p class="sub">{rate_p}</p>

  <footer>
    <a href="{full_href}">&larr; {s['back'].replace('{title}', cfg['title'])}</a><br>
    {cfg['title']} &middot; {cfg['source']} &middot; Matokipedo
    <div class="version">v{version}</div>
  </footer>
</div>
</body>
</html>
"""

def build(base, check=False):
    stale = 0
    for repo, cfg in SITES.items():
        d = Path(base) / repo
        text = (d / "index.html").read_text(encoding="utf-8")
        version = re.search(r'<meta name="app-version" content="([^"]+)"', text).group(1)
        providers = extract_providers(text); chips = extract_chips(text)
        assert providers and chips, repo
        codes = {c for c, _ in chips}
        lite_langs = {c: v for c, v in LITE_REUSE[cfg["site"]].items() if c in codes and v[0] in STRINGS}
        m = re.search(r'const LITE_LANGS = (\[[^\]]*\]);', text)
        declared = json.loads(m.group(1)) if m else None
        if declared != list(lite_langs):
            print(f"{repo}/index.html: LITE_LANGS is {declared} but the generator builds {list(lite_langs)} — update index.html"); stale += 1
        # strings are keyed by source language; map chip code -> string set
        wanted = {"lite.html"}
        for lang in ["en"] + list(lite_langs):
            key = "en" if lang == "en" else lite_langs[lang][0]
            if key != lang: STRINGS[lang] = STRINGS[key]
            out = render(cfg, version, providers, chips, lang, lite_langs)
            p = d / page_name(lang); wanted.add(p.name)
            old = p.read_text(encoding="utf-8") if p.exists() else None
            if old != out:
                stale += 1
                if not check: p.write_text(out, encoding="utf-8")
            print(f"{repo}/{p.name}: {len(providers)} providers, {'unchanged' if old == out else ('WOULD UPDATE' if check else 'written')}")
        for extra in sorted(d.glob("lite-*.html")):
            if extra.name not in wanted: print(f"{repo}/{extra.name}: ORPHAN (no longer generated — delete it)"); stale += 1
    return stale

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    n = build(args[0] if args else ".", check="--check" in sys.argv)
    sys.exit(1 if ("--check" in sys.argv and n) else 0)
