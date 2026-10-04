# Changelog

All notable changes to SkillGuide Forever are documented here.

## 0.4.0 - 2026-10-03

### Added
- Public skin/integration API (`SkillGuideForeverAPI`) with create/show/hide/refresh callbacks for ElvUI, AddOnSkins, and similar tools
- Built-in **Flat Dark** and **Midnight Gold** test skins (same callback path as external skinners) selectable under Window skin
- Esc → Options → AddOns settings: window skin, external skins, window scale, frame strata, Addon Compartment
- Addon Compartment entry plus `/sg config` / `/pg config`
- Stable widget handles on each frame (`SkillGuideForeverWidgets`) for third-party skinners
- Professions **Hide recipes** filter and a cleaner three-row toolbar (no count subtitle)

## 0.3.0 - 2026-10-03

### Added
- Shift-click (CHATLINK) a skill or profession recipe to insert a rich spell link into an open chat box

### Changed
- Profession skill-up breakpoints show as colored `##/##/##/##` (orange/yellow/green/grey) instead of an `O/Y/G/Gray` label
- Removed the Profession label beside the dropdown; both toolbars clear the large frame portrait
- Replaced Unicode dash/dot separators with ASCII so the client renders cleanly

## 0.2.0 - 2026-10-03

### Added
- Professions mode with its own window (`/pg` or `/skillguideprofessions`)
- Class skills slash command shortened to `/sg`
- Profession dropdown covering primary + secondary skills
- Recipe list with learn skill level, trainer/recipe source, and skill-up color breakpoints
- Hide known + search for profession recipes
- Wowhead Forever profession seed (`Core/ProfessionData.lua`) via the same `update-data.ps1` / `extract_wowhead.py` pipeline

## 0.1.0 - 2026-10-03

### Added
- Forever-only skill browser (`## Interface: 16001`)
- Class dropdown for all 9 classes (defaults to your class)
- Skill list with icon, name, rank, and train level
- Own-class cues: available / known / locked coloring
- Hide known toggle (saved)
- Search box (name, rank, level)
- Forever skill seed from Wowhead ability listviews
- `update-data.ps1` / `tools/extract_wowhead.py` for regenerating seed data
