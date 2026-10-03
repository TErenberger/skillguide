# SkillGuide Forever

A **WoW Forever** addon that lists class trainer skills, ranks, and the level required to train them. Defaults to your current class; use the dropdown to browse any class.

![Interface](https://img.shields.io/badge/Interface-16001-blue) ![License](https://img.shields.io/badge/License-MIT-green)

## Features

- Class dropdown for all 9 classes
- Icon, name, rank, and train level for each skill
- Own-class cues: available / known / locked
- **Hide known** toggle
- Search by name, rank, or level
- Forever skill seed (not Classic Era tables)

## Install

### From a zip / CurseForge / Wago

Install normally with your addon client, or unpack so you have:

`World of Warcraft\_classic_beta_\Interface\AddOns\SkillGuideForever\SkillGuideForever.toc`

Restart the client (or `/reload`).

### From this repo (developers)

```powershell
.\update-data.ps1 -Deploy
```

## Usage

| Command | Action |
|---------|--------|
| `/skillguideforever` or `/sgf` | Toggle the window |

- **Class** dropdown — browse another class
- **Hide known** — hide skills you already learned (your class only)
- Search box — filter the list

Colors on your own class: green = can train, grey = known, red = locked.

## Updating / releasing (authors)

After a Forever patch, ship a new CurseForge build in one command:

```powershell
.\release.ps1 -UpdateData -Bump patch -Push
```

That refreshes Wowhead skill data, bumps the version, tags `vX.Y.Z`, and lets GitHub Actions upload to CurseForge.

One-time CurseForge automation setup (project ID + API token) is in [RELEASE.md](RELEASE.md).

| Script | Purpose |
|--------|---------|
| `.\release.ps1 -UpdateData -Bump patch -Push` | Full automated release |
| `.\update-data.ps1 -Deploy` | Refresh data into local AddOns only |
| `.\package.ps1 -Version 0.1.1` | Manual zip (no upload) |

See also [PUBLISHING.md](PUBLISHING.md).

## License

MIT — see [LICENSE](LICENSE).

Skill seed data is generated from [Wowhead Forever ability listviews](https://www.wowhead.com/forever/spells/abilities/). Re-run `update-data.ps1` to refresh.
