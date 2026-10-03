<#
.SYNOPSIS
  Refresh skill data (optional), bump version, commit, tag, and push a release.

  Pushing tag vX.Y.Z triggers .github/workflows/release.yml which packages the
  addon and uploads to CurseForge (when CF_API_KEY + X-Curse-Project-ID are set).

.EXAMPLE
  # After a Forever patch: pull new Wowhead data and ship a patch release
  .\release.ps1 -UpdateData -Bump patch -Push

.EXAMPLE
  # Code-only release, no data refresh
  .\release.ps1 -Bump patch -Message "Fix search box focus" -Push

.EXAMPLE
  # Preview what would happen
  .\release.ps1 -UpdateData -Bump patch -DryRun
#>
[CmdletBinding()]
param(
    [switch]$UpdateData,
    [ValidateSet("major", "minor", "patch", "none")]
    [string]$Bump = "patch",
    [string]$Version = "",
    [string]$Message = "",
    [switch]$Push,
    [switch]$DryRun,
    [switch]$SkipCommit
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

function Get-TocVersion {
    $toc = Get-Content ".\SkillGuideForever.toc" -Raw
    if ($toc -match '(?m)^## Version:\s*(.+)$') {
        return $Matches[1].Trim()
    }
    throw "Could not read ## Version from SkillGuideForever.toc"
}

function Set-TocVersion([string]$newVersion) {
    $tocPath = ".\SkillGuideForever.toc"
    $toc = Get-Content $tocPath -Raw
    $updated = [regex]::Replace($toc, '(?m)^## Version:\s*.+$', "## Version: $newVersion")
    Set-Content -Path $tocPath -Value $updated -NoNewline -Encoding UTF8
}

function Bump-Version([string]$current, [string]$kind) {
    if ($kind -eq "none") { return $current }
    $parts = $current.Split(".")
    while ($parts.Count -lt 3) { $parts += "0" }
    $major = [int]$parts[0]; $minor = [int]$parts[1]; $patch = [int]$parts[2]
    switch ($kind) {
        "major" { $major++; $minor = 0; $patch = 0 }
        "minor" { $minor++; $patch = 0 }
        "patch" { $patch++ }
    }
    return "$major.$minor.$patch"
}

function Ensure-CurseReady {
    $toc = Get-Content ".\SkillGuideForever.toc" -Raw
    $hasId = $toc -match '(?m)^## X-Curse-Project-ID:\s*\d+\s*$'
    if (-not $hasId) {
        Write-Host ""
        Write-Host "WARNING: ## X-Curse-Project-ID is missing from SkillGuideForever.toc" -ForegroundColor Yellow
        Write-Host "  Find it on https://authors.curseforge.com/ (Project ID on your project page)." -ForegroundColor Yellow
        Write-Host "  Add:  ## X-Curse-Project-ID: YOUR_ID" -ForegroundColor Yellow
        Write-Host "  Without it, GitHub Release still works but CurseForge upload is skipped." -ForegroundColor Yellow
        Write-Host ""
    }

    $secrets = gh secret list -R TErenberger/skillguide 2>$null
    if (-not ($secrets -match "CF_API_KEY")) {
        Write-Host "WARNING: GitHub secret CF_API_KEY is not set." -ForegroundColor Yellow
        Write-Host "  Create a token at https://authors.curseforge.com/account/api-tokens" -ForegroundColor Yellow
        Write-Host "  Then run:  gh secret set CF_API_KEY -R TErenberger/skillguide" -ForegroundColor Yellow
        Write-Host ""
    }
}

$oldVersion = Get-TocVersion
if ($Version) {
    $newVersion = $Version
} else {
    $newVersion = Bump-Version $oldVersion $Bump
}

if (-not $Message) {
    if ($UpdateData) {
        $Message = "Update Forever skill seed for $newVersion"
    } else {
        $Message = "Release $newVersion"
    }
}

Write-Host "SkillGuide Forever release" -ForegroundColor Cyan
Write-Host "  version : $oldVersion -> $newVersion"
Write-Host "  data    : $(if ($UpdateData) { 'refresh from Wowhead' } else { 'keep existing' })"
Write-Host "  push    : $Push"
Write-Host "  dry-run : $DryRun"
Write-Host ""

Ensure-CurseReady

if ($UpdateData) {
    Write-Host "Refreshing skill data from Wowhead..." -ForegroundColor Cyan
    if ($DryRun) {
        & python ".\tools\extract_wowhead.py" --dry-run
        if ($LASTEXITCODE -ne 0) { throw "Data dry-run failed" }
    } else {
        & python ".\tools\extract_wowhead.py"
        if ($LASTEXITCODE -ne 0) { throw "Data update failed" }
    }
}

if ($DryRun) {
    Write-Host "Dry run complete. No files committed or tagged." -ForegroundColor Green
    exit 0
}

Set-TocVersion $newVersion

$date = (Get-Date).ToString("yyyy-MM-dd")
$changelogPath = ".\CHANGELOG.md"
$changelog = Get-Content $changelogPath -Raw
$entry = @"
## $newVersion - $date

### Changed
- $Message

"@
if ($changelog -notmatch [regex]::Escape("## $newVersion ")) {
    $changelog = $changelog -replace '(# Changelog\r?\n\r?\n)', ("`$1" + $entry)
    Set-Content -Path $changelogPath -Value $changelog -NoNewline -Encoding UTF8
}

if (-not $SkipCommit) {
    git add SkillGuideForever.toc CHANGELOG.md Core/Data.lua Core/ProfessionData.lua
    # Stage other tracked changes if present (UI fixes etc.)
    git add -u
    $status = git status --porcelain
    if (-not $status) {
        Write-Host "Nothing to commit (working tree clean)." -ForegroundColor Yellow
    } else {
        git commit -m "$Message"
    }

    $tag = "v$newVersion"
    $existing = git tag -l $tag
    if ($existing) {
        throw "Tag $tag already exists. Bump version or delete the tag first."
    }
    git tag -a $tag -m "SkillGuide Forever $newVersion"

    if ($Push) {
        git push origin HEAD
        git push origin $tag
        Write-Host ""
        Write-Host "Pushed $tag. GitHub Actions will package and upload." -ForegroundColor Green
        Write-Host "Watch: https://github.com/TErenberger/skillguide/actions" -ForegroundColor Green
        Write-Host "CurseForge: https://www.curseforge.com/wow/addons/skillguideforever" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "Created local commit + tag $tag." -ForegroundColor Green
        Write-Host "Push when ready:" -ForegroundColor Cyan
        Write-Host "  git push origin HEAD"
        Write-Host "  git push origin $tag"
    }
}
