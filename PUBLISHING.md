# Publishing SkillGuide Forever

Checklist for shipping SkillGuide Forever to CurseForge, Wago, and WoWInterface.

## Prerequisites

- [ ] GitHub CLI authenticated: `gh auth login`
- [ ] Python 3 on PATH (for data updates)
- [ ] CurseForge author account
- [ ] Wago Addons author account (optional but recommended)
- [ ] WoWInterface author account (optional)

## 1. Finish local prep

```powershell
.\update-data.ps1 -Deploy
.\package.ps1 -Version 0.1.0
```

Smoke-test in Forever beta (`/sgf`) after `/reload`.

Player zip lands in `dist\SkillGuideForever-0.1.0.zip` with layout:

```
SkillGuideForever/
  SkillGuideForever.toc
  SkillGuideForever.lua
  Core/...
  UI/...
  README.md
  CHANGELOG.md
  LICENSE
```

## 2. GitHub repository

Already at: https://github.com/TErenberger/skillguide

## 3. Create host projects (manual, one-time)

### CurseForge

1. Open [CurseForge Authors](https://authors.curseforge.com/) → create project **SkillGuide Forever** / slug `skillguide-forever`
2. Game: World of Warcraft → flavor **Forever**
3. Category: Class / Utility
4. Paste the CurseForge summary from `media/curseforge-description.html` (or README marketing copy)
5. Upload logo from `media/` if present
6. Note the numeric **Project ID**
7. Create an [API token](https://authors.curseforge.com/account/api-tokens)

### Wago / WoWInterface

Same idea: create **SkillGuide Forever**, Forever game type, note project IDs and API tokens.

## 4. Wire project IDs into the TOC

Add these lines to `SkillGuideForever.toc`:

```toc
## X-Curse-Project-ID: 123456
## X-Wago-ID: aBcDeFgH
## X-WoWI-ID: 98765
```

## 5. GitHub Actions secrets

| Secret | Value |
|--------|--------|
| `CF_API_KEY` | CurseForge API token |
| `WAGO_API_TOKEN` | Wago API token |
| `WOWI_API_TOKEN` | WoWInterface API token |

## 6. First release

```powershell
.\package.ps1 -Version 0.1.0
```

Upload `dist\SkillGuideForever-0.1.0.zip` as **Beta**, then later:

```powershell
git tag v0.1.0
git push origin v0.1.0
```

## 7. Ongoing updates

```powershell
.\update-data.ps1 -Deploy
# bump ## Version in SkillGuideForever.toc + CHANGELOG.md
git commit -am "Update Forever skill seed"
git tag v0.1.1
git push origin master v0.1.1
```
