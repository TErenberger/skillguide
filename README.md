# SkillGuide Forever

**What can I train next — and what am I still missing?**

SkillGuide Forever is a lightweight WoW Forever addon that shows class trainer skills and profession recipes in a clean Blizzard-style window. See ranks, the level (or skill) you need, and whether something is ready to learn, already known, or still locked.

Made for **WoW Forever** — not Classic Era leftovers.

## Why grab it

- Plan your next trainer visit without guessing
- Peek at other classes when you’re theorycrafting an alt
- Check profession recipes: when you can learn them, trainer vs recipe, skill-up colors
- Hide stuff you already know so the list stays useful while leveling
- Search when you only remember half a spell name

## Commands

| Type this | What opens |
|-----------|------------|
| `/sg` | Class skills |
| `/pg` | Profession recipes |
| `/sg config` | Options (also Esc → Options → AddOns) |

That’s it. Pick a class or profession from the dropdown, optionally turn on **Hide known**, and go.

Open chat, then **Shift-click** a row to paste a clickable spell/recipe link.

Works with popular UI packs: turn on **Allow external skins** in options so ElvUI / AddOnSkins can restyle the windows. Skin authors can hook `SkillGuideForeverAPI`.

**Colors on your character:** green = you can learn it now · grey = already known · red = not yet (level or skill too low).

## Install

Install with CurseForge (or your usual addon client), then restart the game or type `/reload`.

[Get it on CurseForge](https://www.curseforge.com/wow/addons/skillguideforever)

Manual install: put the `SkillGuideForever` folder in  
`World of Warcraft\_classic_beta_\Interface\AddOns\`  
so that `SkillGuideForever.toc` is inside that folder.

## Notes

- Built for **WoW Forever**
- Pet abilities / warlock grimoires are not listed
- Gathering professions may show fewer entries than crafts (that’s the data, not a broken filter)

## License

MIT — see [LICENSE](LICENSE).
