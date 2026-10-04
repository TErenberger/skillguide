"""
Fetch WoW Forever class + profession data from Wowhead and write Core Lua seeds.

Examples:
  python tools/extract_wowhead.py
  python tools/extract_wowhead.py --deploy
  python tools/extract_wowhead.py --class hunter --deploy
  python tools/extract_wowhead.py --professions-only --deploy
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
import time
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

# (wowhead slug, data key, path prefix)
PROFESSIONS = [
    ("alchemy", "ALCHEMY", "professions"),
    ("blacksmithing", "BLACKSMITHING", "professions"),
    ("enchanting", "ENCHANTING", "professions"),
    ("engineering", "ENGINEERING", "professions"),
    ("herbalism", "HERBALISM", "professions"),
    ("leatherworking", "LEATHERWORKING", "professions"),
    ("mining", "MINING", "professions"),
    ("skinning", "SKINNING", "professions"),
    ("tailoring", "TAILORING", "professions"),
    ("cooking", "COOKING", "secondary-skills"),
    ("first-aid", "FIRST_AID", "secondary-skills"),
    ("fishing", "FISHING", "secondary-skills"),
]

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT_DIR = pathlib.Path(__file__).resolve().parent / "_cache"
DATA_LUA = ROOT / "Core" / "Data.lua"
PROFESSION_DATA_LUA = ROOT / "Core" / "ProfessionData.lua"
DEFAULT_ADDONS = pathlib.Path(
    r"C:\Program Files\World of Warcraft\_classic_beta_\Interface\AddOns\SkillGuideForever"
)
SSL_CTX = ssl._create_unverified_context()
USER_AGENT = "SkillGuideForeverDataUpdater/1.0 (+local forever seed refresh)"


def fetch(url: str, *, retries: int = 4, timeout: int = 30) -> str:
    last_err = None
    for attempt in range(retries):
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as resp:
                return resp.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as exc:
            last_err = exc
            # Wowhead occasionally 403/429's bursty spell-page fetches.
            if exc.code in (403, 429, 503) and attempt + 1 < retries:
                time.sleep(2.0 * (attempt + 1))
                continue
            raise
        except urllib.error.URLError as exc:
            last_err = exc
            if attempt + 1 < retries:
                time.sleep(1.0 * (attempt + 1))
                continue
            raise
    raise last_err  # pragma: no cover


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


# Wowhead ability listview source ids (see listview filters).
SOURCE_DROP = 2  # tome / drop ranks (e.g. some max ranks)
SOURCE_QUEST = 4
SOURCE_TRAINER = 6

# Classic Era / Forever spell ids stay below this; 400k-1.2M is mostly
# Season of Discovery / Cata leftovers that leak onto Forever listviews.
CLASSIC_SPELL_ID_MAX = 100_000
# Forever-authored spell ids observed on trainer rows (Lava Burst, Penance, …).
FOREVER_SPELL_ID_MIN = 1_200_000

# Auto-learned utilities that never get a trainer/quest source tag.
AUTO_LEARNED_NAMES = {
    "auto shot",
    "battle stance",
    "berserker stance",
    "call pet",
    "defensive stance",
    "dismiss pet",
    "feed pet",
    "revive pet",
}


def source_ids(item: dict) -> list:
    sources = item.get("source") or []
    if not isinstance(sources, list):
        sources = [sources]
    return [s for s in sources if s is not None]


def has_trainer_source(item: dict) -> bool:
    return (SOURCE_TRAINER in source_ids(item)) or (item.get("trainingcost") is not None)


def has_quest_source(item: dict) -> bool:
    return SOURCE_QUEST in source_ids(item)


def has_drop_source(item: dict) -> bool:
    return SOURCE_DROP in source_ids(item)


def env_status(item: dict) -> str | None:
    env = item.get("envChange") or {}
    if not isinstance(env, dict):
        return None
    status = env.get("status")
    return str(status) if status else None


def is_noise_name(name: str) -> bool:
    lower = name.lower()
    if not name:
        return True
    if lower.startswith(("improved ", "engrave ", "glyph of ", "test ")):
        return True
    # Talent-tree passive ranks that sometimes lack a source tag.
    if lower.endswith((" specialization", " mastery")):
        return True
    return False


def class_skill_lines(item: dict) -> list:
    skill = item.get("skill") or []
    if not isinstance(skill, list):
        skill = [skill] if skill else []
    return [s for s in skill if s]


def parse_training_cost(item: dict) -> int:
    cost = item.get("trainingcost")
    try:
        cost = int(cost) if cost is not None else 0
    except (TypeError, ValueError):
        cost = 0
    return cost if cost > 0 else 0


def passes_base_filters(row: dict, item: dict) -> bool:
    """Reject obvious non-abilities before Forever availability checks."""
    if row["level"] <= 0:
        return False
    if is_noise_name(row["name"]):
        return False
    if not class_skill_lines(item):
        return False
    if env_status(item) == "removed":
        return False
    return True


def is_forever_available_row(row: dict, item: dict, sourced_names: set) -> bool:
    """Keep only abilities that exist for players in WoW Forever.

    Wowhead's Forever ability listviews also include unsigned SoD/Cata spell
    rows (Lava Lash, Healing Rain, …). Those have no trainer/quest/drop source
    and mid-range spell ids, so they are dropped here.
    """
    if row.get("trainer") or row.get("quest") or row.get("drop"):
        return True

    sid = int(row["spellID"])
    name_key = (row.get("name") or "").lower()
    src = source_ids(item)
    status = env_status(item)

    # Earlier ranks / auto-learns of trainer/quest/book abilities.
    if not src and sid < CLASSIC_SPELL_ID_MAX:
        if name_key in sourced_names or name_key in AUTO_LEARNED_NAMES:
            return True
        if row["level"] <= 1:
            return True

    # Unique Forever-authored spells sometimes lack a source tag. Skip when a
    # trainer/quest/book sibling already covers the ability name (duplicates).
    if (
        not src
        and sid >= FOREVER_SPELL_ID_MIN
        and status == "new"
        and name_key not in sourced_names
    ):
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
    candidates = []
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
        quest = has_quest_source(item)
        drop = has_drop_source(item)
        cost = parse_training_cost(item)

        row = {
            "spellID": int(sid),
            "rank": rank,
            "level": level,
            "name": name,
            "quest": bool(quest),
            "drop": bool(drop),
            "trainer": bool(trainer),
            "cost": cost,
        }
        if passes_base_filters(row, item):
            candidates.append((row, item))

    sourced_names = {
        (row.get("name") or "").lower()
        for row, _item in candidates
        if row.get("trainer") or row.get("quest") or row.get("drop")
    }

    rows = []
    skipped_unsigned = 0
    for row, item in candidates:
        if is_forever_available_row(row, item, sourced_names):
            # Internal helper flag; not written to Lua.
            row = {
                "spellID": row["spellID"],
                "rank": row["rank"],
                "level": row["level"],
                "name": row["name"],
                "quest": row["quest"],
                "trainer": row["trainer"],
                "cost": row["cost"],
            }
            rows.append(row)
        else:
            skipped_unsigned += 1

    by_key = {}
    for r in rows:
        key = (r["name"].lower(), r["rank"])
        prev = by_key.get(key)
        if not prev:
            by_key[key] = r
            continue
        prev_score = (
            1 if prev["trainer"] else 0,
            1 if prev["quest"] else 0,
            prev["spellID"],
        )
        new_score = (
            1 if r["trainer"] else 0,
            1 if r["quest"] else 0,
            r["spellID"],
        )
        if new_score > prev_score:
            by_key[key] = r

    rows = sorted(
        by_key.values(), key=lambda r: (r["level"], r["name"].lower(), r["spellID"])
    )
    (OUT_DIR / ("wh_%s.json" % class_slug)).write_text(
        json.dumps(rows, indent=2), encoding="utf-8"
    )
    print(
        "         %s: %d skills (trainer=%d quest=%d; skipped %d unsigned)"
        % (
            class_slug,
            len(rows),
            sum(1 for r in rows if r.get("trainer")),
            sum(1 for r in rows if r.get("quest")),
            skipped_unsigned,
        )
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
            flags = ""
            if s.get("quest"):
                flags += ", quest = true"
            cost = int(s.get("cost") or 0)
            if cost > 0:
                flags += ", cost = %d" % cost
            name = (s.get("name") or "").replace("\\", "\\\\").replace('"', '\\"')
            lines.append(
                '\t\t{ spellID = %d, rank = %d, level = %d, name = "%s"%s },'
                % (s["spellID"], s["rank"], s["level"], name, flags)
            )
        lines.append("\t},")
    lines.append("}")
    lines.append("")
    DATA_LUA.parent.mkdir(parents=True, exist_ok=True)
    DATA_LUA.write_text("\n".join(lines) + "\n", encoding="utf-8")


def extract_profession(slug: str, key: str, prefix: str, *, from_cache: bool = False):
    cache_html = OUT_DIR / ("wh_prof_%s.html" % slug.replace("-", "_"))
    url = "https://www.wowhead.com/forever/spells/%s/%s" % (prefix, slug)

    if from_cache:
        if not cache_html.exists():
            raise FileNotFoundError("No cache for profession %s (%s)" % (slug, cache_html))
        print("  cache  %s" % slug)
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
        learned = item.get("learnedat")
        if learned is None:
            continue
        try:
            skill = int(learned)
        except (TypeError, ValueError):
            continue
        # Wowhead uses 9999 for the profession skill header / unavailable rows.
        if skill >= 9000:
            continue
        name = item.get("displayName") or item.get("name") or ""
        if not name:
            continue
        # Skip the bare profession skill entry ("Alchemy", "Cooking", ...).
        if name.replace(" ", "-").lower() == slug or name.lower() == slug.replace("-", " "):
            if not item.get("colors"):
                continue

        sources = item.get("source") or []
        if not isinstance(sources, list):
            sources = [sources]
        trainer = (6 in sources) or (item.get("trainingcost") is not None)
        cost = item.get("trainingcost")
        try:
            cost = int(cost) if cost is not None else 0
        except (TypeError, ValueError):
            cost = 0
        if cost < 0:
            cost = 0
        colors = item.get("colors") or []
        orange = int(colors[0]) if len(colors) > 0 else skill
        yellow = int(colors[1]) if len(colors) > 1 else skill
        green = int(colors[2]) if len(colors) > 2 else skill
        gray = int(colors[3]) if len(colors) > 3 else skill
        # Wowhead often leaves colors[0] as 0 for drop/recipe-taught spells.
        # learnedat is the required profession skill to learn it (same value
        # shown on the teaching recipe as "Requires <Profession> (N)").
        if orange <= 0:
            if skill > 0:
                orange = skill
            elif yellow > 0:
                # Starter recipes (learnedat 0): orange band starts at 1.
                orange = 1
            else:
                orange = 0

        rows.append(
            {
                "spellID": int(sid),
                "skill": skill,
                "name": name,
                "trainer": bool(trainer),
                "cost": cost,
                "orange": orange,
                "yellow": yellow,
                "green": green,
                "gray": gray,
            }
        )

    by_id = {}
    for r in rows:
        prev = by_id.get(r["spellID"])
        if not prev or r["skill"] < prev["skill"]:
            by_id[r["spellID"]] = r
    rows = sorted(by_id.values(), key=lambda r: (r["skill"], r["name"].lower(), r["spellID"]))
    (OUT_DIR / ("wh_prof_%s.json" % slug.replace("-", "_"))).write_text(
        json.dumps(rows, indent=2), encoding="utf-8"
    )
    print(
        "         %s: %d recipes (%d trainer)"
        % (slug, len(rows), sum(1 for r in rows if r["trainer"]))
    )
    return rows


def write_profession_data_lua(all_data: dict, generated_at: str):
    lines = [
        "-- Forever profession recipe seed for SkillGuideForever.",
        "-- Source: Wowhead Forever profession / secondary-skill listviews",
        "--   https://www.wowhead.com/forever/spells/professions/",
        "--   https://www.wowhead.com/forever/spells/secondary-skills/",
        "-- Generated: %s" % generated_at,
        "-- Update: python tools/extract_wowhead.py   or   .\\update-data.ps1",
        "local addonName, ns = ...",
        "",
        "ns.ProfessionData = {",
    ]
    for _, key, _ in PROFESSIONS:
        lines.append("\t%s = {" % key)
        for s in all_data.get(key, []):
            trainer = ", trainer = true" if s.get("trainer") else ""
            cost = int(s.get("cost") or 0)
            cost_field = (", cost = %d" % cost) if cost > 0 else ""
            name = (s.get("name") or "").replace("\\", "\\\\").replace('"', '\\"')
            lines.append(
                "\t\t{ spellID = %d, skill = %d, name = \"%s\", "
                "orange = %d, yellow = %d, green = %d, gray = %d%s%s },"
                % (
                    s["spellID"],
                    s["skill"],
                    name,
                    s["orange"],
                    s["yellow"],
                    s["green"],
                    s["gray"],
                    trainer,
                    cost_field,
                )
            )
        lines.append("\t},")
    lines.append("}")
    lines.append("")
    PROFESSION_DATA_LUA.parent.mkdir(parents=True, exist_ok=True)
    PROFESSION_DATA_LUA.write_text("\n".join(lines) + "\n", encoding="utf-8")


def deploy_to_addons(addons_dir: pathlib.Path):
    core = addons_dir / "Core"
    core.mkdir(parents=True, exist_ok=True)
    if DATA_LUA.exists():
        shutil.copy2(DATA_LUA, core / "Data.lua")
        print("deployed -> %s" % (core / "Data.lua"))
    if PROFESSION_DATA_LUA.exists():
        shutil.copy2(PROFESSION_DATA_LUA, core / "ProfessionData.lua")
        print("deployed -> %s" % (core / "ProfessionData.lua"))


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="Update SkillGuideForever class + profession seeds from Wowhead."
    )
    p.add_argument(
        "--class",
        dest="classes",
        action="append",
        choices=CLASSES,
        help="Only refresh one class (repeatable).",
    )
    p.add_argument(
        "--profession",
        dest="professions",
        action="append",
        choices=[p[0] for p in PROFESSIONS],
        help="Only refresh one profession (repeatable).",
    )
    p.add_argument(
        "--classes-only",
        action="store_true",
        help="Refresh class skills only.",
    )
    p.add_argument(
        "--professions-only",
        action="store_true",
        help="Refresh profession recipes only.",
    )
    p.add_argument(
        "--from-cache",
        action="store_true",
        help="Rebuild Lua from tools/_cache HTML (no network).",
    )
    p.add_argument(
        "--deploy",
        action="store_true",
        help="Copy seed Lua files into the WoW Forever AddOns folder.",
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
        help="Fetch/parse and print counts only; do not write Lua.",
    )
    return p.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    do_classes = not args.professions_only
    do_professions = not args.classes_only
    if args.classes:
        do_classes = True
    if args.professions:
        do_professions = True

    print("SkillGuideForever data update")
    print("  mode         : %s" % ("cache" if args.from_cache else "live Wowhead"))
    print("  classes      : %s" % ("yes" if do_classes else "skip"))
    print("  professions  : %s" % ("yes" if do_professions else "skip"))
    print("")

    class_data = {}
    prof_data = {}
    all_json_path = OUT_DIR / "all.json"
    prof_json_path = OUT_DIR / "all_professions.json"

    if do_classes and args.classes and all_json_path.exists():
        try:
            class_data.update(json.loads(all_json_path.read_text(encoding="utf-8")))
        except json.JSONDecodeError:
            pass
    if do_professions and args.professions and prof_json_path.exists():
        try:
            prof_data.update(json.loads(prof_json_path.read_text(encoding="utf-8")))
        except json.JSONDecodeError:
            pass

    try:
        if do_classes:
            selected = args.classes or CLASSES
            print("Classes")
            for c in selected:
                class_data[c.upper()] = extract_class(c, from_cache=args.from_cache)
            for c in CLASSES:
                class_data.setdefault(c.upper(), [])

        if do_professions:
            selected_prof = args.professions or [p[0] for p in PROFESSIONS]
            print("Professions")
            for slug, key, prefix in PROFESSIONS:
                if slug not in selected_prof:
                    continue
                prof_data[key] = extract_profession(
                    slug, key, prefix, from_cache=args.from_cache
                )
            for _, key, _ in PROFESSIONS:
                prof_data.setdefault(key, [])
    except (urllib.error.URLError, urllib.error.HTTPError, ValueError, OSError) as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 1

    class_total = sum(len(v) for v in class_data.values()) if do_classes else 0
    prof_total = sum(len(v) for v in prof_data.values()) if do_professions else 0
    print("")
    if do_classes:
        print("summary : %d class skills across %d classes" % (class_total, len(CLASSES)))
    if do_professions:
        print(
            "summary : %d profession recipes across %d professions"
            % (prof_total, len(PROFESSIONS))
        )

    if args.dry_run:
        print("dry-run : Lua files not written")
        return 0

    if do_classes:
        all_json_path.write_text(json.dumps(class_data, indent=2), encoding="utf-8")
        write_data_lua(class_data, generated_at)
        print("wrote   : %s (%d bytes)" % (DATA_LUA, DATA_LUA.stat().st_size))
    if do_professions:
        prof_json_path.write_text(json.dumps(prof_data, indent=2), encoding="utf-8")
        write_profession_data_lua(prof_data, generated_at)
        print(
            "wrote   : %s (%d bytes)"
            % (PROFESSION_DATA_LUA, PROFESSION_DATA_LUA.stat().st_size)
        )

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
        print("next    : .\\update-data.ps1 -Deploy")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
