# Changelog

All notable changes to SkillGuide Forever are documented here.

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
