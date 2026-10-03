# Releasing SkillGuide Forever

Ship a new build to **GitHub Releases**, **CurseForge**, and **Wago** (optional WoWInterface) with one tag or one Actions click.

## One-time setup

### 1. CurseForge (already done if Project ID is in the TOC)

1. Project ID → `## X-Curse-Project-ID` in [`SkillGuideForever.toc`](SkillGuideForever.toc) (currently `1723468`)
2. API token → GitHub secret:

```powershell
gh secret set CF_API_KEY -R TErenberger/skillguide
```

Create a token at: https://authors.curseforge.com/account/api-tokens

### 2. Wago Addons (recommended)

1. Create **SkillGuide Forever** on [addons.wago.io](https://addons.wago.io/) (game type: **Classic Forever**)
2. Copy the 8-character project id from the developer dashboard
3. Add to the TOC:

```toc
## X-Wago-ID: aBcDeFgH
```

4. Store the API token:

```powershell
gh secret set WAGO_API_TOKEN -R TErenberger/skillguide
```

Token page: https://addons.wago.io/account/apikeys

### 3. WoWInterface (optional)

```toc
## X-WoWI-ID: 12345
```

```powershell
gh secret set WOWI_API_TOKEN -R TErenberger/skillguide
```

### 4. GitHub Actions permissions

Repo **Settings → Actions → General → Workflow permissions** → **Read and write** so the packager can create GitHub Releases.

---

## How to release

### A) From your PC (still the easiest after a Forever patch)

```powershell
.\release.ps1 -UpdateData -Bump patch -Push
```

That refreshes Wowhead data, bumps `## Version`, commits, tags `vX.Y.Z`, and pushes.  
The tag triggers [`.github/workflows/release.yml`](.github/workflows/release.yml).

Code-only:

```powershell
.\release.ps1 -Bump patch -Message "Fix dropdown" -Push
```

### B) From GitHub Actions (no local tag needed)

1. Open **Actions → Release → Run workflow**
2. Choose a mode:

| Mode | What it does |
|------|----------------|
| `publish-tag` | Package/upload an existing tag (e.g. `v0.3.0`) |
| `bump-and-publish` | Bump patch/minor/major, commit, tag, then package/upload |

3. Optionally check **skip_upload** to only build the zip (dry packaging)

Watch the run summary for which hosts will receive the file (CurseForge / Wago / GitHub).

### C) Manual zip (no Actions)

```powershell
.\package.ps1 -Version 0.3.1
.\upload-curseforge.ps1 -Version 0.3.1
```

---

## What the workflow uploads

| Target | Needs |
|--------|--------|
| GitHub Release | `contents: write` (workflow already sets this) |
| CurseForge | `CF_API_KEY` + `## X-Curse-Project-ID` |
| Wago | `WAGO_API_TOKEN` + `## X-Wago-ID` |
| WoWInterface | `WOWI_API_TOKEN` + `## X-WoWI-ID` |

Missing secrets are skipped (they do not fail the whole job). GitHub Release still publishes when upload is enabled.

Artifact label/name uses a `-forever` suffix so Forever builds are obvious next to other flavors.

---

## Suggested Forever-patch habit

1. Smoke-test locally (`.\update-data.ps1 -Deploy`, `/reload`, `/sg` + `/pg`)
2. `.\release.ps1 -UpdateData -Bump patch -Push` **or** Actions → **bump-and-publish**
3. Confirm the Actions summary + CurseForge/Wago file lists

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| GitHub Release missing | Enable read/write workflow permissions |
| CurseForge skipped | Check `CF_API_KEY` secret + TOC project id |
| Wago skipped | Create Wago project, set `## X-Wago-ID`, add `WAGO_API_TOKEN` |
| Actions won't run | Billing/payment method on the GitHub account/org; use `.\package.ps1` + `.\upload-curseforge.ps1` meanwhile |
