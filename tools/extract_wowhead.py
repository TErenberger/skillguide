"""
Fetch WoW Forever class trainer skills from Wowhead and write Core/Data.lua.

Examples:
  python tools/extract_wowhead.py
  python tools/extract_wowhead.py --deploy
  python tools/extract_wowhead.py --class hunter --deploy
  python tools/extract_wowhead.py --from-cache
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import shutil
import ssl
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

CLASSES = [
    "warrior",
    "paladin",
    "hunter",
    "rogue",
    "priest",
    "shaman",
    "mage",
    "warlock",
    "druid",
]

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT_DIR = pathlib.Path(__file__).resolve().parent / "_cache"
DATA_LUA = ROOT / "Core" / "Data.lua"
DEFAULT_ADDONS = pathlib.Path(
    r"C:\Program Files\World of Warcraft\_classic_beta_\Interface\AddOns\SkillGuideForever"
)
SSL_CTX = ssl._create_unverified_context()
USER_AGENT = "SkillGuideForeverDataUpdater/1.0 (+local forever seed refresh)"


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=90, context=SSL_CTX) as resp:
        return resp.read().decode("utf-8", "replace")


def extract_balanced_any(source: str, start: int) -> str:
    stack = []
    in_str = False
    esc = False
    pairs = {"{": "}", "[": "]"}
    for i in range(start, len(source)):
        ch = source[i]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
            continue
        if ch in pairs:
            stack.append(pairs[ch])
        elif stack and ch == stack[-1]:
            stack.pop()
            if not stack:
                return source[start : i + 1]
    raise ValueError("unbalanced structure in Wowhead page")


def js_to_json(js: str):
    """Convert Wowhead listview JS literals to JSON (bare keys only outside strings)."""
    out = []
    i = 0
    n = len(js)
    in_str = False
    esc = False
    while i < n:
        ch = js[i]
        if in_str:
            out.append(ch)
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            i += 1
            continue
        if ch == '"':
            in_str = True
            out.append(ch)
            i += 1
            continue
        if ch in "{[,":
            out.append(ch)
            i += 1
            while i < n and js[i].isspace():
                out.append(js[i])
                i += 1
            if i < n and (js[i].isalpha() or js[i] == "_"):
                start = i
                i += 1
                while i < n and (js[i].isalnum() or js[i] == "_"):
                    i += 1
                j = i
                while j < n and js[j].isspace():
                    j += 1
                if j < n and js[j] == ":":
                    out.append('"%s"' % js[start:i])
                    out.append(js[i:j])
                    out.append(":")
                    i = j + 1
                    continue
                out.append(js[start:i])
            continue
        out.append(ch)
        i += 1

    fixed = re.sub(r",\s*([}\]])", r"\1", "".join(out))
    return json.loads(fixed)


def normalize_rank(rank_text) -> int:
    if not rank_text:
        return 0
    m = re.search(r"(\d+)", str(rank_text))
    return int(m.group(1)) if m else 0


def parse_listviewspells(html: str):
    m = re.search(r"listviewspells\s*=\s*\[", html)
    if not m:
        raise ValueError("listviewspells array not found (Wowhead page layout may have changed)")
    raw = extract_balanced_any(html, m.end() - 1)
    return js_to_json(raw)


def has_trainer_source(item: dict) -> bool:
    sources = item.get("source") or []
    if not isinstance(sources, list):
        sources = [sources]
    return (6 in sources) or (item.get("trainingcost") is not None)


def is_noise_name(name: str) -> bool:
    lower = name.lower()
    if not name:
        return True
    return lower.startswith(("improved ", "engrave ", "glyph of ", "test "))


def class_skill_lines(item: dict) -> list:
    skill = item.get("skill") or []
    if not isinstance(skill, list):
        skill = [skill] if skill else []
    return [s for s in skill if s]


def should_keep_row(row: dict, item: dict) -> bool:
    if row["level"] <= 0:
        return False
    if is_noise_name(row["name"]):
        return False
    if not class_skill_lines(item):
        return False
    if row["trainer"]:
        return True
    env = item.get("envChange") or {}
    if isinstance(env, dict) and env.get("status") == "new":
        return True
    if row["spellID"] >= 1_200_000:
        return True
    return False


def extract_class(class_slug: str, *, from_cache: bool = False) -> list:
    cache_html = OUT_DIR / ("wh_%s.html" % class_slug)
    url = "https://www.wowhead.com/forever/spells/abilities/%s" % class_slug

    if from_cache:
        if not cache_html.exists():
            raise FileNotFoundError("No cache for %s (%s)" % (class_slug, cache_html))
        print("  cache  %s" % class_slug)
        html = cache_html.read_text(encoding="utf-8")
    else:
        print("  fetch  %s" % url)
        html = fetch(url)
        cache_html.write_text(html, encoding="utf-8")

    items = parse_listviewspells(html)
    rows = []
    for item in items:
        if not isinstance(item, dict):
            continue
        sid = item.get("id")
        if not sid:
            continue
        name = item.get("displayName") or item.get("name") or ""
        rank = normalize_rank(item.get("rank"))
        level = int(item.get("level") or 0)
        trainer = has_trainer_source(item)
        labels = []
        env = item.get("envChange") or {}
        if isinstance(env, dict):
            labels = [str(x).lower() for x in (env.get("labels") or [])]
        talent = ("talent" in labels) or (
            not trainer and name.lower().startswith("improved ")
        )

        row = {
            "spellID": int(sid),
            "rank": rank,
            "level": level,
            "name": name,
            "talent": bool(talent),
            "trainer": bool(trainer),
        }
        if should_keep_row(row, item):
            rows.append(row)

    by_key = {}
    for r in rows:
        key = (r["name"].lower(), r["rank"])
        prev = by_key.get(key)
        if not prev:
            by_key[key] = r
            continue
        prev_score = (1 if prev["trainer"] else 0, prev["spellID"])
        new_score = (1 if r["trainer"] else 0, r["spellID"])
        if new_score > prev_score:
            by_key[key] = r

    rows = sorted(
        by_key.values(), key=lambda r: (r["level"], r["name"].lower(), r["spellID"])
    )
    (OUT_DIR / ("wh_%s.json" % class_slug)).write_text(
        json.dumps(rows, indent=2), encoding="utf-8"
    )
    print(
        "         %s: %d skills (%d trainer-tagged)"
        % (class_slug, len(rows), sum(1 for r in rows if r["trainer"]))
    )
    return rows


def write_data_lua(all_data: dict, generated_at: str):
    lines = [
        "-- Forever class skill seed for SkillGuideForever.",
        "-- Source: Wowhead Forever ability listviews",
        "--   https://www.wowhead.com/forever/spells/abilities/",
        "-- Generated: %s" % generated_at,
        "-- Update: python tools/extract_wowhead.py   or   .\\update-data.ps1",
        "local addonName, ns = ...",
        "",
        "ns.SkillData = {",
    ]
    for class_file in [c.upper() for c in CLASSES]:
        lines.append("\t%s = {" % class_file)
        for s in all_data.get(class_file, []):
            talent = ", talent = true" if s.get("talent") else ""
            name = (s.get("name") or "").replace("\\", "\\\\").replace('"', '\\"')
            lines.append(
                '\t\t{ spellID = %d, rank = %d, level = %d, name = "%s"%s },'
                % (s["spellID"], s["rank"], s["level"], name, talent)
            )
        lines.append("\t},")
    lines.append("}")
    lines.append("")
    DATA_LUA.parent.mkdir(parents=True, exist_ok=True)
    DATA_LUA.write_text("\n".join(lines) + "\n", encoding="utf-8")


def deploy_to_addons(addons_dir: pathlib.Path):
    dest = addons_dir / "Core" / "Data.lua"
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(DATA_LUA, dest)
    print("deployed -> %s" % dest)


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="Update SkillGuideForever Forever skill seed from Wowhead."
    )
    p.add_argument(
        "--class",
        dest="classes",
        action="append",
        choices=CLASSES,
        help="Only refresh one class (repeatable). Default: all classes.",
    )
    p.add_argument(
        "--from-cache",
        action="store_true",
        help="Rebuild Data.lua from tools/_cache HTML (no network).",
    )
    p.add_argument(
        "--deploy",
        action="store_true",
        help="Copy Core/Data.lua into the WoW Forever AddOns folder.",
    )
    p.add_argument(
        "--addons-dir",
        type=pathlib.Path,
        default=DEFAULT_ADDONS,
        help="SkillGuideForever AddOns folder (used with --deploy).",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Fetch/parse and print counts only; do not write Data.lua.",
    )
    return p.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    selected = args.classes or CLASSES
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    print("SkillGuideForever data update")
    print("  mode    : %s" % ("cache" if args.from_cache else "live Wowhead"))
    print("  classes : %s" % ", ".join(selected))
    print("")

    all_data = {}
    # Preserve non-selected classes from existing all.json when partial refresh
    all_json_path = OUT_DIR / "all.json"
    if args.classes and all_json_path.exists():
        try:
            all_data.update(json.loads(all_json_path.read_text(encoding="utf-8")))
        except json.JSONDecodeError:
            pass

    try:
        for c in selected:
            all_data[c.upper()] = extract_class(c, from_cache=args.from_cache)
    except (urllib.error.URLError, urllib.error.HTTPError, ValueError, OSError) as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 1

    # Ensure every class key exists for full Data.lua writes
    for c in CLASSES:
        all_data.setdefault(c.upper(), [])

    total = sum(len(v) for v in all_data.values())
    print("")
    print("summary : %d skills across %d classes" % (total, len(CLASSES)))

    if args.dry_run:
        print("dry-run : Data.lua not written")
        return 0

    all_json_path.write_text(json.dumps(all_data, indent=2), encoding="utf-8")
    write_data_lua(all_data, generated_at)
    print("wrote   : %s (%d bytes)" % (DATA_LUA, DATA_LUA.stat().st_size))

    if args.deploy:
        if not args.addons_dir.exists():
            print(
                "ERROR: AddOns folder not found: %s" % args.addons_dir,
                file=sys.stderr,
            )
            return 1
        deploy_to_addons(args.addons_dir)
        print("next    : /reload in-game")
    else:
        print("next    : .\\update-data.ps1 -Deploy   (or copy Core\\Data.lua yourself)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
