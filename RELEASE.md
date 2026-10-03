# Releasing SkillGuide Forever

Goal: after a Forever patch (or any code change), ship a new CurseForge build with as little clicking as possible.

## One-time setup (do this once)

### 1. CurseForge project ID

1. Open [CurseForge Authors](https://authors.curseforge.com/) → **SkillGuide Forever**
2. Copy the numeric **Project ID**
3. Add it to [`SkillGuideForever.toc`](SkillGuideForever.toc):

```toc
## X-Curse-Project-ID: 1234567
```

Commit that change.

### 2. CurseForge API token → GitHub secret

1. Create a token: https://authors.curseforge.com/account/api-tokens  
2. Store it on the repo:

```powershell
gh secret set CF_API_KEY -R TErenberger/skillguide
```

(Paste the token when prompted.)

Optional later: `WAGO_API_TOKEN`, `WOWI_API_TOKEN` the same way.

### 3. Confirm the release workflow exists

Pushing a tag `v*` runs [`.github/workflows/release.yml`](.github/workflows/release.yml) using [BigWigs packager](https://github.com/BigWigsMods/packager). It builds the zip and uploads to CurseForge when the project ID + `CF_API_KEY` are set.

---

## Everyday release (after a patch)

From the repo root:

```powershell
.\release.ps1 -UpdateData -Bump patch -Push
```

That will:

1. Pull latest Forever skill lists from Wowhead into `Core/Data.lua`
2. Bump `## Version` (patch: `0.1.0` → `0.1.1`)
3. Prepend a CHANGELOG entry
4. Commit + create tag `v0.1.1`
5. Push branch + tag → GitHub Actions publishes to CurseForge

Watch progress: https://github.com/TErenberger/skillguide/actions

### Other common commands

| Goal | Command |
|------|---------|
| Data refresh + release | `.\release.ps1 -UpdateData -Bump patch -Push` |
| Code fix only | `.\release.ps1 -Bump patch -Message "Fix dropdown" -Push` |
| Preview (no commit) | `.\release.ps1 -UpdateData -Bump patch -DryRun` |
| Manual zip (no CF upload) | `.\package.ps1 -Version 0.1.1` |
| Local AddOns deploy only | `.\update-data.ps1 -Deploy` |

---

## Suggested Forever-patch habit

1. `.\release.ps1 -UpdateData -Bump patch -Push`
2. In-game `/reload`, spot-check `/sg` and `/pg`
3. If something looks wrong, fix, then `.\release.ps1 -Bump patch -Message "Fix …" -Push`

You do **not** need to re-upload a zip in the CurseForge UI once secrets + project ID are wired.
