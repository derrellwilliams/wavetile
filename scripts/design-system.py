#!/usr/bin/env python3
"""Generates docs/design-system.html, the Wavetile design system gallery, from the code.

Everything on the page is read from source, so the page is the code's design system, not a copy:
tokens and their doc comments from Theme.swift and Motion.swift, icons from Glyph.swift and the
Icons.xcassets SVGs, components from DesignSystem/Components, and every "Used in" list from a scan
of the app's Swift files. Re-run after changing any of those:

    scripts/design-system.py           # write docs/design-system.html
    scripts/design-system.py --check   # exit 1 if the page is out of date
"""

import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KIT = ROOT / "Packages/WavetileKit/Sources"
DS = KIT / "DesignSystem"
OUT = ROOT / "docs/design-system.html"
SCAN = [KIT, ROOT / "App", ROOT / "Widgets", ROOT / "Shared"]
FONTS = "../Packages/WavetileKit/Sources/DesignSystem/Resources/Fonts"


# MARK: - Source reading

def read(path):
    return path.read_text(encoding="utf-8")


def block(text, opener):
    """The brace-balanced body that follows `opener` (a struct, or a call's parentheses)."""
    start = text.index(opener) + len(opener)
    open_ch = text[start - 1] if text[start - 1] in "({[" else None
    if open_ch is None:
        start = min(i for i in (text.find("{", start), text.find("(", start)) if i != -1) + 1
        open_ch = text[start - 1]
    close_ch = {"{": "}", "(": ")", "[": "]"}[open_ch]
    depth = 1
    for i in range(start, len(text)):
        depth += {open_ch: 1, close_ch: -1}.get(text[i], 0)
        if depth == 0:
            return text[start:i]
    raise ValueError(f"unbalanced {opener}")


def declarations(body, pattern):
    """(match, doc comment) for each line matching `pattern`, with the `///` lines just above it."""
    found, doc = [], []
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("///"):
            doc.append(stripped[3:].strip())
            continue
        match = re.match(pattern, stripped)
        if match:
            found.append((match, " ".join(doc)))
        doc = []
    return found


def doc_above(text, needle):
    """The `///` comment directly above the line containing `needle`."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if needle in line:
            doc = []
            j = i - 1
            while j >= 0 and lines[j].strip().startswith("///"):
                doc.insert(0, lines[j].strip()[3:].strip())
                j -= 1
            return " ".join(doc)
    return ""


SWIFT_FILES = sorted(p for root in SCAN if root.exists() for p in root.rglob("*.swift"))
SOURCES = {p: read(p).splitlines() for p in SWIFT_FILES}


def uses(pattern, exclude=()):
    """Every line in the app matching `pattern`, as (path, line number, code)."""
    regex = re.compile(pattern)
    hits = []
    for path, lines in SOURCES.items():
        if path.name in exclude:
            continue
        for n, line in enumerate(lines, 1):
            code = line.strip()
            if regex.search(line) and not code.startswith("//"):
                hits.append((path.relative_to(ROOT), n, code))
    return hits


# MARK: - Tokens

theme = read(DS / "Theme.swift")
dark = block(theme, "public static let dark = Theme(")
light = block(theme, "static let light: Theme = {")


def hex_color(expr):
    """CSS for a Swift color expression from Theme.swift."""
    m = re.search(r"Color\(hex: 0x([0-9A-Fa-f]{6})\)(?:\.opacity\(([\d.]+)\))?", expr)
    if m:
        rgb = "#" + m.group(1).upper()
        return rgb if not m.group(2) else f"{rgb} @ {float(m.group(2)):g}"
    m = re.search(r"\.(black|white)\.opacity\(([\d.]+)\)", expr)
    if m:
        return f"{'#000000' if m.group(1) == 'black' else '#FFFFFF'} @ {float(m.group(2)):g}"
    return None


def css_color(value):
    rgb, _, alpha = value.partition(" @ ")
    if not alpha:
        return rgb
    r, g, b = (int(rgb[i:i + 2], 16) for i in (1, 3, 5))
    return f"rgba({r},{g},{b},{alpha})"


palette_struct = block(theme, "public struct Palette")
palette = []
for m, doc in declarations(palette_struct, r"public var (\w+)(?:: (\w+|\[Color\]))?(?: = (.*)| \{ (.*) \})?$"):
    name, default, computed = m.group(1), m.group(3), m.group(4)
    palette.append({"name": name, "doc": doc, "default": default, "computed": computed})

dark_palette = block(dark, "palette: .init(")
light_overrides = dict(re.findall(r"theme\.palette\.(\w+) = (.+)", light))


def palette_values(entry, source, overrides):
    name = entry["name"]
    if entry["computed"]:  # derived from another token, e.g. accent.opacity(0.12)
        m = re.match(r"(\w+)\.opacity\(([\d.]+)\)", entry["computed"])
        base = resolve_palette(m.group(1), source, overrides)[0]
        return [f"{base.split(' @ ')[0]} @ {float(m.group(2)):g}"]
    expr = overrides.get(name) or (re.search(rf"\b{name}: (.+)", source) or [None, entry["default"] or ""])[1]
    if expr.strip().startswith("["):
        return [hex_color(c) for c in re.findall(r"Color\([^)]*\)", expr)]
    return [hex_color(expr)]


def resolve_palette(name, source, overrides):
    entry = next(e for e in palette if e["name"] == name)
    return palette_values(entry, source, overrides)


for entry in palette:
    entry["dark"] = palette_values(entry, dark_palette, {})
    entry["light"] = palette_values(entry, dark_palette, light_overrides)
    entry["uses"] = uses(rf"palette\.{entry['name']}\b", exclude=("Theme.swift",))

typography_struct = block(theme, "public struct Typography")
scale = dict((k, int(v)) for k, v in re.findall(r"(\w+): CGFloat\((\d+)\)", typography_struct.split("\n")[1]))


def mono_size(style):
    """`Typography.mono(_:)`'s size for a text style."""
    if style in ("caption", "caption2", "footnote"):
        return scale["caption"]
    return scale["body"] if style in ("body", "callout", "headline") else scale["small"]


# Sizes are `Typography.scale` steps (or literals); `Typography.mono(.style)` picks its own.
type_values = {
    name: {"style": style, "size": scale[size] if size in scale else int(size), "mono": bool(mono)}
    for name, style, size, mono in re.findall(
        r"(\w+): BrandFont\.font\(\.(\w+), size: (?:Typography\.scale\.)?(\w+)(, family: BrandFont\.monoFamily)?\)", dark)
}
type_values.update({name: {"style": style, "size": mono_size(style), "mono": True}
                    for name, style in re.findall(r"(\w+): Typography\.mono\(\.(\w+)\)", dark)})
typography = []
type_settings = []
for m, doc in declarations(typography_struct, r"public var (\w+): (Font|CGFloat)(?: = (-?[\d.]+))?$"):
    name, kind, value = m.groups()
    if kind == "Font":
        typography.append({"name": name, "doc": re.sub(r"^\d+(, mono)?: ", "", doc), **type_values[name],
                           "uses": uses(rf"typography\.{name}\b", exclude=("Theme.swift",))})
    else:
        type_settings.append({"name": name, "value": value, "doc": doc,
                              "uses": uses(rf"typography\.{name}\b", exclude=("Theme.swift",))})
mono_doc = doc_above(typography_struct, "public func mono(")
mono_uses = uses(r"typography\.mono\(", exclude=("Theme.swift",))
type_doc = doc_above(theme, "public struct Typography")


def number_tokens(struct_name, prefix):
    body = block(theme, f"public struct {struct_name}")
    return [{"name": m.group(1), "value": float(m.group(2)), "doc": doc,
             "uses": uses(rf"{prefix}\.{m.group(1)}\b", exclude=("Theme.swift",))}
            for m, doc in declarations(body, r"public var (\w+): (?:CGFloat|Double) = ([\d.]+)$")]


spacing = number_tokens("Spacing", "spacing")
radius = number_tokens("Radius", "radius")
artwork = number_tokens("Artwork", "artwork")
token = {t["name"]: t["value"] for t in spacing + radius + artwork}

motion_src = read(DS / "Motion.swift")
motion_struct = block(motion_src, "public struct Motion")
motion_standard = block(motion_src, "public static let standard = Motion(")
motion_values = dict(re.findall(r"(\w+): (.+?),?\n", motion_standard + "\n"))
motion = []
for m, doc in declarations(motion_struct, r"public var (\w+): \w+(?: = (.+))?$"):
    name = m.group(1)
    motion.append({"name": name, "doc": doc, "value": motion_values.get(name) or m.group(2) or "",
                   "uses": uses(rf"motion\.{name}\b", exclude=("Motion.swift",))})
motion_doc = doc_above(motion_src, "public struct Motion")

glyph_src = read(DS / "Glyph.swift")
glyph_doc = doc_above(glyph_src, "public enum Glyph")
icons = []
for case, asset in re.findall(r"^\s*case `?(\w+)`?(?: = \"([\w-]+)\")?$", block(glyph_src, "public enum Glyph"), re.M):
    asset = asset or case
    svg_path = DS / f"Resources/Icons.xcassets/{asset}.imageset/{asset}.svg"
    svg = read(svg_path) if svg_path.exists() else ""
    svg = re.sub(r'fill="#0+"', 'fill="currentColor"', re.sub(r' (width|height)="\d+"', "", svg))
    # By name (`glyph: .trash`, `Glyph.trash`), any `.name` on a line that mentions a glyph (ternaries),
    # or a case returned from a `var glyph: Glyph` switch (`case .genres: .genre`).
    named = uses(rf"(Glyph\.|[gG]lyph: \.){case}\b", exclude=("Glyph.swift",))
    nearby = uses(rf"(?=.*[gG]lyph).*\.{case}\b", exclude=("Glyph.swift",))
    switched = [hit for hit in uses(rf"^\s*case [^:]+: \.{case}$", exclude=("Glyph.swift",))
                if any(": Glyph {" in line for line in SOURCES[ROOT / hit[0]])]
    hits = sorted(set(named) | set(nearby) | set(switched))
    icons.append({"case": case, "asset": asset, "svg": svg, "uses": hits})

components = []
for path in sorted((DS / "Components").glob("*.swift")):
    src = read(path)
    for kind, name in re.findall(r"^public (struct|enum) (\w+)", src, re.M):
        components.append({"name": name, "file": path.relative_to(ROOT), "doc": doc_above(src, f"public {kind} {name}"),
                           "uses": uses(rf"\b{name}\b(?!\.swift)", exclude=(path.name,))})


# MARK: - HTML

def esc(s):
    return html.escape(str(s), quote=True)


def md(s):
    """Doc comments use `code` spans."""
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", esc(s))


def num(v):
    return f"{v:g}"


def used_in(hits, limit=60):
    if not hits:
        return '<span class="none">No direct references found</span>'
    files = sorted({str(p) for p, _, _ in hits})
    names = ", ".join(sorted({Path(f).stem for f in files}))
    rows = "".join(
        f'<li><span class="loc">{esc(str(p).replace("Packages/WavetileKit/Sources/", ""))}:{n}</span>'
        f"<code>{esc(code[:140])}</code></li>"
        for p, n, code in hits[:limit])
    more = f'<li class="none">…and {len(hits) - limit} more</li>' if len(hits) > limit else ""
    return (f'<details><summary><b>{len(hits)}</b> use{"s" if len(hits) != 1 else ""} in {len(files)} '
            f'file{"s" if len(files) != 1 else ""}: <span class="files">{esc(names)}</span></summary>'
            f"<ul>{rows}{more}</ul></details>")


def section(id_, title, intro, body):
    return f'<section id="{id_}"><h2>{title}</h2>{f"<p class=lead>{intro}</p>" if intro else ""}{body}</section>'


def swatch(value):
    return f'<span class="swatch" style="background:{css_color(value)}"></span><code>{esc(value)}</code>'


colors = "".join(
    f'<tr><td><code>palette.{e["name"]}</code><p>{md(e["doc"])}</p></td>'
    f'<td>{"<br>".join(swatch(v) for v in e["dark"])}</td>'
    f'<td>{"<br>".join(swatch(v) for v in e["light"])}</td>'
    f'<td>{used_in(e["uses"])}</td></tr>'
    for e in palette)
colors = f'<table><tr><th>Token</th><th>Dark (default)</th><th>Light</th><th>Used in</th></tr>{colors}</table>'

scale_row = "".join(f'<div class="step"><span style="font-size:{v}px">Aa</span><code>{v} · {k}</code></div>'
                    for k, v in scale.items())
type_rows = "".join(
    f'<tr><td><code>typography.{t["name"]}</code><p>{md(t["doc"])}</p></td>'
    f'<td><code>{t["size"]}</code><br><span class="dim">{"Geist Mono" if t["mono"] else "Inter"} · .{t["style"]}</span></td>'
    f'<td><div class="sample {"mono" if t["mono"] else ""}" style="font-size:{t["size"]}px'
    f'{";letter-spacing:" + num(next(float(s["value"]) for s in type_settings if s["name"] == "displayTracking")) + "px" if t["size"] >= 36 and not t["mono"] else ""}">'
    f'{"4 · 2 · 7 · 1" if t["name"] == "code" else "3:42 · 2019 · 12 tracks" if t["mono"] else "Spirit of Eden"}</div></td>'
    f'<td>{used_in(t["uses"])}</td></tr>'
    for t in typography)
type_rows += (f'<tr><td><code>typography.mono(_:)</code><p>{md(mono_doc)}</p></td><td><code>12 / 14 / 16</code>'
              f'<br><span class="dim">Geist Mono</span></td><td><div class="sample mono" style="font-size:12px">3:42</div>'
              f'<div class="sample mono" style="font-size:16px">2019 · 41 min</div></td><td>{used_in(mono_uses)}</td></tr>')
type_rows += "".join(
    f'<tr><td><code>typography.{s["name"]}</code><p>{md(s["doc"])}</p></td><td><code>{esc(s["value"])}</code></td>'
    f'<td></td><td>{used_in(s["uses"])}</td></tr>' for s in type_settings)
typography_html = (f'<p class="lead">{md(type_doc)}</p><div class="scale">{scale_row}</div>'
                   f'<table><tr><th>Token</th><th>Size · face</th><th>Sample</th><th>Used in</th></tr>{type_rows}</table>')


def doc_p(doc):
    return f"<p>{md(doc)}</p>" if doc else ""


def number_table(tokens, prefix, visual):
    rows = "".join(
        f'<tr><td><code>{prefix}.{t["name"]}</code>{doc_p(t["doc"])}</td>'
        f'<td><code>{num(t["value"])}</code></td><td>{visual(t)}</td><td>{used_in(t["uses"])}</td></tr>'
        for t in tokens)
    return f'<table><tr><th>Token</th><th>pt</th><th></th><th>Used in</th></tr>{rows}</table>'


def size_visual(t):
    v = t["value"]
    if t["name"].startswith("shadow"):
        return ""
    return f'<span class="box" style="width:{v}px;height:{v}px"></span>'


spacing_html = number_table(spacing, "spacing", lambda t: f'<span class="bar" style="width:{t["value"]}px"></span>')
radius_html = number_table(radius, "radius",
                           lambda t: f'<span class="box" style="width:56px;height:56px;border-radius:{t["value"]}px"></span>')
artwork_html = number_table(artwork, "artwork", size_visual)

# A Home shelf drawn from the tokens: inset, tile width, gap, header size and gaps.
section_header = next(t for t in typography if t["name"] == "sectionHeader")
item_title = next(t for t in typography if t["name"] == "itemTitle")
tile = token["shelfTileWidth"]


def mock_shelf(title, n):
    tiles = "".join(f'<div class="tile" style="width:{tile}px"><div class="art" style="height:{tile}px"></div>'
                    f'<div style="font-size:{item_title["size"]}px">Album {i + 1}</div>'
                    f'<div class="dim" style="font-size:{item_title["size"]}px">Artist</div></div>' for i in range(n))
    return (f'<div style="padding:0 {token["screenInset"]}px;font-size:{section_header["size"]}px;'
            f'margin-bottom:{token["md"]}px">{title}</div>'
            f'<div class="row" style="gap:{token["lg"]}px;padding-left:{token["screenInset"]}px">{tiles}</div>')


anatomy = (
    f'<div class="phone">{mock_shelf("Recently Played", 3)}<div style="height:{token["xxl"]}px" class="gap">'
    f'<span>spacing.xxl · {num(token["xxl"])}</span></div>{mock_shelf("Most Played", 3)}</div>'
    f'<ul class="legend"><li><code>spacing.screenInset</code> {num(token["screenInset"])}: screen edge to header and first tile</li>'
    f'<li><code>typography.sectionHeader</code> {section_header["size"]}: shelf title</li>'
    f'<li><code>spacing.md</code> {num(token["md"])}: title to artwork</li>'
    f'<li><code>artwork.shelfTileWidth</code> {num(tile)}: tile and artwork width</li>'
    f'<li><code>spacing.lg</code> {num(token["lg"])}: gap between tiles</li>'
    f'<li><code>typography.itemTitle</code> / <code>itemSubtitle</code> {item_title["size"]}: album and artist</li>'
    f'<li><code>spacing.xxl</code> {num(token["xxl"])}: gap between shelves (HomeView)</li></ul>')

motion_rows = "".join(
    f'<tr><td><code>motion.{m["name"]}</code><p>{md(m["doc"])}</p></td><td><code>{esc(m["value"])}</code></td>'
    f'<td>{used_in(m["uses"])}</td></tr>' for m in motion)
motion_html = (f'<p class="lead">{md(motion_doc)}</p><table><tr><th>Token</th><th>Standard</th><th>Used in</th></tr>'
               f"{motion_rows}</table>")

icon_cards = "".join(
    f'<details class="icon"><summary>{i["svg"]}<code>.{i["case"]}</code><span class="dim">{i["asset"]}</span>'
    f'<span class="count">{len(i["uses"]) or "–"}</span></summary>{used_in(i["uses"], 20)}</details>'
    for i in icons)
icons_html = f'<p class="lead">{md(glyph_doc)}</p><div class="icons">{icon_cards}</div>'

component_rows = "".join(
    f'<tr><td><code>{c["name"]}</code><br><span class="dim">{esc(c["file"].name)}</span></td><td>{md(c["doc"])}</td>'
    f'<td>{used_in(c["uses"])}</td></tr>' for c in components)
components_html = f'<table><tr><th>Component</th><th>What it is</th><th>Used in</th></tr>{component_rows}</table>'

nav = [("color", "Color"), ("type", "Type"), ("spacing", "Spacing"), ("shelf", "Shelf anatomy"), ("radius", "Radius"),
       ("artwork", "Artwork"), ("motion", "Motion"), ("icons", "Icons"), ("components", "Components")]
bg, fg = css_color(resolve_palette("background", dark_palette, {})[0]), css_color(resolve_palette("textPrimary", dark_palette, {})[0])
subtle = css_color(resolve_palette("textSecondary", dark_palette, {})[0])
surface = css_color(resolve_palette("surface", dark_palette, {})[0])
line = css_color(resolve_palette("separator", dark_palette, {})[0])

page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Wavetile design system</title>
<!-- Generated by scripts/design-system.py from the Swift sources. Don't edit; re-run the script. -->
<style>
@font-face {{ font-family: Inter; src: url("{FONTS}/Inter-Regular.otf"); }}
@font-face {{ font-family: "Geist Mono"; src: url("{FONTS}/GeistMono-Regular.otf"); }}
:root {{ --bg: {bg}; --fg: {fg}; --subtle: {subtle}; --surface: {surface}; --line: {line}; }}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.4 Inter, system-ui, sans-serif; }}
code, .mono {{ font-family: "Geist Mono", ui-monospace, monospace; font-size: 13px; }}
.sample.mono {{ font-size: inherit; }}
nav {{ position: sticky; top: 0; z-index: 2; background: var(--bg); border-bottom: 1px solid var(--line);
  padding: 12px 32px; display: flex; gap: 20px; flex-wrap: wrap; font-size: 14px; }}
nav a {{ color: var(--subtle); text-decoration: none; }} nav a:hover {{ color: var(--fg); }}
header, section {{ max-width: 1240px; margin: 0 auto; padding: 32px; }}
h1 {{ font-weight: 400; font-size: 36px; letter-spacing: -0.5px; margin: 0 0 8px; }}
h2 {{ font-weight: 400; font-size: 22px; margin: 0 0 12px; }}
p {{ margin: 4px 0 0; }} .lead {{ color: var(--subtle); max-width: 760px; margin-bottom: 20px; }}
.dim, .none {{ color: var(--subtle); }} .none {{ font-size: 13px; }}
table {{ width: 100%; border-collapse: collapse; }}
th {{ text-align: left; font-weight: 400; font-size: 12px; color: var(--subtle); padding: 8px 12px 8px 0;
  border-bottom: 1px solid var(--line); }}
td {{ vertical-align: top; padding: 14px 12px 14px 0; border-bottom: 1px solid var(--line); font-size: 14px; }}
td:first-child {{ width: 26%; }} td p {{ color: var(--subtle); font-size: 13px; }}
td:last-child {{ width: 40%; }}
.swatch {{ display: inline-block; width: 28px; height: 28px; vertical-align: middle; margin: 0 8px 4px 0;
  border: 1px solid var(--line); border-radius: 6px; }}
details summary {{ cursor: pointer; color: var(--subtle); font-size: 13px; }}
details summary b {{ color: var(--fg); font-weight: 400; }}
details ul {{ list-style: none; padding: 8px 0 0; margin: 0; max-height: 320px; overflow: auto; }}
details li {{ padding: 3px 0; font-size: 12px; display: flex; flex-direction: column; }}
details li code {{ font-size: 11px; color: var(--subtle); white-space: pre-wrap; word-break: break-all; }}
.loc {{ font-family: "Geist Mono", monospace; font-size: 12px; }}
.files {{ color: var(--fg); }}
.scale {{ display: flex; gap: 28px; align-items: flex-end; flex-wrap: wrap; margin-bottom: 24px; }}
.step {{ display: flex; flex-direction: column; gap: 6px; }} .step code {{ color: var(--subtle); font-size: 12px; }}
.sample {{ line-height: 1.2; white-space: nowrap; }}
.bar {{ display: inline-block; height: 16px; background: var(--fg); border-radius: 2px; }}
.box {{ display: inline-block; background: var(--surface); border: 1px solid var(--subtle); max-width: 160px; max-height: 160px; }}
.phone {{ width: 402px; background: var(--bg); border: 1px solid var(--line); border-radius: 40px; padding: 28px 0;
  overflow: hidden; float: left; margin-right: 40px; }}
.row {{ display: flex; overflow: hidden; }} .tile {{ flex: none; }}
.art {{ background: linear-gradient(135deg, #2E2E2E, #222222); margin-bottom: 6px; }}
.gap {{ position: relative; background: repeating-linear-gradient(45deg, transparent 0 6px, var(--line) 6px 8px); }}
.gap span {{ position: absolute; right: 16px; top: 50%; transform: translateY(-50%); font: 11px "Geist Mono", monospace; color: var(--subtle); }}
.legend {{ list-style: none; padding: 0; font-size: 14px; line-height: 2; }}
#shelf::after {{ content: ""; display: block; clear: both; }}
.icons {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 8px; }}
.icon {{ border: 1px solid var(--line); border-radius: 12px; padding: 12px; }}
.icon[open] {{ grid-column: 1 / -1; }}
.icon summary {{ list-style: none; display: grid; grid-template-columns: 28px 1fr auto; column-gap: 10px; align-items: center; color: var(--fg); }}
.icon summary::-webkit-details-marker {{ display: none; }}
.icon svg {{ width: 24px; height: 24px; grid-row: span 2; }}
.icon .dim {{ font-size: 11px; grid-column: 2; }} .icon .count {{ grid-row: 1 / span 2; grid-column: 3; color: var(--subtle); font-size: 12px; }}
</style>
</head>
<body>
<nav>{"".join(f'<a href="#{i}">{t}</a>' for i, t in nav)}</nav>
<header>
<h1>Wavetile design system</h1>
<p class="lead">Generated from <code>DesignSystem/Theme.swift</code>, <code>Motion.swift</code>, <code>Glyph.swift</code> and
<code>Components/</code> by <code>scripts/design-system.py</code>. The descriptions are the code's own doc comments, and every
“Used in” list is a scan of the app's Swift files. Views read all of this via <code>@Environment(\\.theme)</code>.
Values shown are the Dark theme's; Light changes colors only.</p>
</header>
{section("color", "Color", md(doc_above(theme, "public struct Theme:")), colors)}
{section("type", "Type", "", typography_html)}
{section("spacing", "Spacing", "", spacing_html)}
{section("shelf", "Shelf anatomy", "A Home shelf at 1:1 in points, drawn from the tokens above.", anatomy)}
{section("radius", "Radius", "", radius_html)}
{section("artwork", "Artwork", "", artwork_html)}
{section("motion", "Motion", "", motion_html)}
{section("icons", "Icons", "", icons_html + '<p class="dim">Counts are references found by name (<code>glyph: .name</code>, <code>Glyph.name</code>); conditional ones may be missed. Click an icon for its uses.</p>')}
{section("components", "Components", "Public views in <code>DesignSystem/Components</code>.", components_html)}
</body>
</html>
"""

if "--check" in sys.argv:
    if not OUT.exists() or read(OUT) != page:
        print(f"{OUT.relative_to(ROOT)} is out of date: run scripts/design-system.py", file=sys.stderr)
        sys.exit(1)
    print(f"{OUT.relative_to(ROOT)} is up to date")
else:
    OUT.write_text(page, encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)}: {len(palette)} colors, {len(typography)} type styles, "
          f"{len(spacing)} spacing, {len(icons)} icons, {len(components)} components")
