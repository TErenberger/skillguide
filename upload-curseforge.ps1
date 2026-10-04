<#
.SYNOPSIS
  Upload a packaged SkillGuideForever zip to CurseForge (manual / local path).

.EXAMPLE
  $env:CF_API_KEY = "your-token"
  .\package.ps1 -Version 0.2.0
  .\upload-curseforge.ps1 -Version 0.2.0

.EXAMPLE
  .\upload-curseforge.ps1 -Version 0.2.0 -ApiToken "your-token" -ReleaseType beta
#>
[CmdletBinding()]
param(
    [string]$Version = "0.4.0",
    [string]$ApiToken = $env:CF_API_KEY,
    [ValidateSet("alpha", "beta", "release")]
    [string]$ReleaseType = "release",
    [int]$ProjectId = 1723468,
    [string]$ZipPath = "",
    [string]$ChangelogPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

if (-not $ApiToken) {
    Write-Host ""
    Write-Host "CurseForge API token required." -ForegroundColor Yellow
    Write-Host "Create one at: https://authors.curseforge.com/account/api-tokens"
    Write-Host "Then either:"
    Write-Host '  $env:CF_API_KEY = "paste-token-here"'
    Write-Host "  .\upload-curseforge.ps1 -Version $Version"
    Write-Host "or:"
    Write-Host "  .\upload-curseforge.ps1 -Version $Version -ApiToken `"paste-token-here`""
    Write-Host ""
    throw "CF_API_KEY / -ApiToken missing"
}

if (-not $ZipPath) {
    $ZipPath = Join-Path $repoRoot "dist\SkillGuideForever-$Version.zip"
}
if (-not (Test-Path $ZipPath)) {
    throw "Zip not found: $ZipPath`nRun .\package.ps1 -Version $Version first."
}

if (-not $ChangelogPath) {
    $ChangelogPath = Join-Path $repoRoot "CHANGELOG.md"
}

# Prefer the section for this version; fall back to whole file.
$changelog = Get-Content $ChangelogPath -Raw -Encoding UTF8
$sectionPattern = "(?ms)^##\s+$([regex]::Escape($Version))\b.*?(?=^##\s+|\z)"
$section = [regex]::Match($changelog, $sectionPattern)
if ($section.Success) {
    $changelogBody = $section.Value.Trim()
} else {
    $changelogBody = $changelog.Trim()
}

$headers = @{
    "X-Api-Token" = $ApiToken
    "Accept"      = "application/json"
}

Write-Host "Fetching WoW game versions..." -ForegroundColor Cyan
$versionsUri = "https://wow.curseforge.com/api/game/versions"
$versions = Invoke-RestMethod -Uri $versionsUri -Headers $headers -Method Get

# Prefer Forever / interface 16001 labels.
$chosen = @($versions | Where-Object { $_.name -match '(?i)forever' })
if (-not $chosen -or $chosen.Count -eq 0) {
    $chosen = @($versions | Where-Object { $_.name -match '16001|1\.16' })
}
if (-not $chosen -or $chosen.Count -eq 0) {
    Write-Host "Could not auto-pick Forever game versions. Available sample:" -ForegroundColor Yellow
    $versions | Sort-Object name -Descending | Select-Object -First 60 name, id | Format-Table -AutoSize
    throw "No Forever game version matched. Inspect the list and pass -GameVersionIds."
}

$gameVersionIds = @($chosen | Sort-Object id -Descending | Select-Object -First 5 -ExpandProperty id)
$chosenNames = @($chosen | Where-Object { $gameVersionIds -contains $_.id } | ForEach-Object { $_.name })
Write-Host ("Using gameVersions: {0}" -f (($chosen | Where-Object { $gameVersionIds -contains $_.id } | ForEach-Object { "$($_.name)[$($_.id)]" }) -join ", "))

$metadataObj = [ordered]@{
    changelog     = $changelogBody
    changelogType = "markdown"
    displayName   = $Version
    gameVersions  = $gameVersionIds
    releaseType   = $ReleaseType
}
$metadata = $metadataObj | ConvertTo-Json -Compress

Write-Host "Uploading $ZipPath to project $ProjectId ($ReleaseType)..." -ForegroundColor Cyan

# Multipart form: metadata + file
$form = @{
    metadata = $metadata
    file     = Get-Item -LiteralPath $ZipPath
}

$uploadUri = "https://wow.curseforge.com/api/projects/$ProjectId/upload-file"
try {
    $response = Invoke-RestMethod -Uri $uploadUri -Headers $headers -Method Post -Form $form
} catch {
    $err = $_
    if ($err.ErrorDetails -and $err.ErrorDetails.Message) {
        Write-Host $err.ErrorDetails.Message -ForegroundColor Red
    }
    throw
}

Write-Host "Upload succeeded." -ForegroundColor Green
$response | ConvertTo-Json -Depth 6
Write-Host "Project: https://www.curseforge.com/wow/addons/skillguideforever/files"
Write-Host "Authors: https://authors.curseforge.com/"
