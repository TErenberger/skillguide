# Publishing SkillGuide

Checklist for shipping SkillGuide to CurseForge, Wago, and WoWInterface.

## Prerequisites

- [ ] GitHub CLI authenticated: `gh auth login`
- [ ] Python 3 on PATH (for data updates)
- [ ] CurseForge author account
- [ ] Wago Addons author account (optional but recommended)
- [ ] WoWInterface author account (optional)

## 1. Finish local prep

```powershell
# Refresh Forever skill seed + deploy to your beta client
.\update-data.ps1 -Deploy

# Build a manual upload zip
.\package.ps1 -Version 0.1.0
```

Smoke-test in Forever beta (`/sg`) after `/reload`.

Player zip lands in `dist\SkillGuide-0.1.0.zip` with layout:

```
SkillGuide/
  SkillGuide.toc
  SkillGuide.lua
  Core/...
  UI/...
  README.md
  CHANGELOG.md
  LICENSE
```

## 2. Create the GitHub repository

From the repo root (after the initial commit exists):

```powershell
gh auth login
gh repo create skillguide --public --source=. --remote=origin --push
```

Suggested topics: `world-of-warcraft`, `wow-addon`, `wow-forever`.

## 3. Create host projects (manual, one-time)

### CurseForge

1. Open [CurseForge Authors](https://authors.curseforge.com/) → create project **SkillGuide**
2. Game: World of Warcraft → flavor **Forever** (or Camelot if still labeled that way)
3. Category: Class / Utility
4. Paste README description + upload 2–4 screenshots
5. Note the numeric **Project ID**
6. Create an [API token](https://authors.curseforge.com/account/api-tokens)

### Wago Addons

1. Open [addons.wago.io](https://addons.wago.io/) → create addon
2. Select Forever / matching game type
3. Note the **Wago ID**
4. Create an API token under account settings

### WoWInterface

1. Create the file/project on [wowinterface.com](https://www.wowinterface.com/)
2. Note the numeric file ID
3. Create an API token under file management

## 4. Wire project IDs into the TOC

Add these lines to `SkillGuide.toc` (use your real IDs):

```toc
## X-Curse-Project-ID: 123456
## X-Wago-ID: aBcDeFgH
## X-WoWI-ID: 98765
```

Commit that change.

## 5. Add GitHub Actions secrets

Repo → Settings → Secrets and variables → Actions:

| Secret | Value |
|--------|--------|
| `CF_API_KEY` | CurseForge API token |
| `WAGO_API_TOKEN` | Wago API token |
| `WOWI_API_TOKEN` | WoWInterface API token |

`GITHUB_TOKEN` is provided automatically for GitHub Releases.

## 6. First release

### Manual (recommended once)

1. `.\package.ps1 -Version 0.1.0`
2. Upload `dist\SkillGuide-0.1.0.zip` as **Beta** on CurseForge / Wago
3. Confirm the CurseForge/Wago client installs and loads it

### Automated (after IDs + secrets)

```powershell
git tag v0.1.0
git push origin v0.1.0
```

The [release workflow](.github/workflows/release.yml) runs [BigWigsMods/packager](https://github.com/BigWigsMods/packager), builds the zip from `.pkgmeta`, and uploads to every host that has a secret + TOC project ID.

## 7. Ongoing updates

When Forever trainer data changes:

```powershell
.\update-data.ps1 -Deploy
# bump ## Version in SkillGuide.toc + CHANGELOG.md
git commit -am "Update Forever skill seed"
git tag v0.1.1
git push origin master v0.1.1
```

At Forever launch, re-check `## Interface:` (beta is `16001`) and ship a TOC bump if Blizzard changes it.

## Notes

- `tools/` and `update-data.*` are **not** included in player zips (see `.pkgmeta`).
- Skill data is derived from Wowhead Forever ability listviews; keep the attribution in `Core/Data.lua` / README.
- Prefer **Beta** release type until Forever launches, then switch to Release.
