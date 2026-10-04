<#
.SYNOPSIS
  Upload a packaged SkillGuideForever zip to Wago Addons (local path).

.EXAMPLE
  $env:WAGO_API_TOKEN = "your-token"
  .\package.ps1
  .\upload-wago.ps1

.EXAMPLE
  .\upload-wago.ps1 -Version 0.4.0 -ApiToken "your-token" -ReleaseType beta
#>
[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$ApiToken = $env:WAGO_API_TOKEN,
    [ValidateSet("alpha", "beta", "release")]
    [string]$ReleaseType = "release",
    [string]$ProjectId = "",
    [string]$ZipPath = "",
    [string]$ChangelogPath = "",
    [string]$ForeverPatch = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

$secrets = Join-Path $repoRoot "scripts\Import-LocalSecrets.ps1"
if (Test-Path $secrets) {
    & $secrets
    if (-not $ApiToken) {
        $ApiToken = $env:WAGO_API_TOKEN
    }
}

function Get-TocField([string]$field) {
    $toc = Get-Content (Join-Path $repoRoot "SkillGuideForever.toc") -Raw
    $pattern = "(?m)^##\s+$([regex]::Escape($field)):\s*(.+)$"
    if ($toc -match $pattern) {
        return $Matches[1].Trim()
    }
    return $null
}

if (-not $Version) {
    $Version = Get-TocField "Version"
}
if (-not $Version) {
    throw "Could not determine version (pass -Version or set ## Version in TOC)."
}

if (-not $ProjectId) {
    $ProjectId = Get-TocField "X-Wago-ID"
}
if (-not $ProjectId) {
    throw "Missing ## X-Wago-ID in SkillGuideForever.toc (or pass -ProjectId)."
}

if (-not $ApiToken) {
    Write-Host ""
    Write-Host "Wago API token required." -ForegroundColor Yellow
    Write-Host "Create one at: https://addons.wago.io/account/apikeys"
    Write-Host "Then either:"
    Write-Host '  $env:WAGO_API_TOKEN = "paste-token-here"'
    Write-Host "  .\upload-wago.ps1 -Version $Version"
    Write-Host "or put WAGO_API_TOKEN=... in a local .env file."
    Write-Host ""
    throw "WAGO_API_TOKEN / -ApiToken missing"
}

if (-not $ZipPath) {
    $ZipPath = Join-Path $repoRoot "dist\SkillGuideForever-$Version.zip"
}
if (-not (Test-Path -LiteralPath $ZipPath)) {
    throw "Zip not found: $ZipPath`nRun .\package.ps1 -Version $Version first."
}

if (-not $ChangelogPath) {
    $ChangelogPath = Join-Path $repoRoot "CHANGELOG.md"
}

$changelog = Get-Content $ChangelogPath -Raw -Encoding UTF8
$sectionPattern = "(?ms)^##\s+$([regex]::Escape($Version))\b.*?(?=^##\s+|\z)"
$section = [regex]::Match($changelog, $sectionPattern)
if ($section.Success) {
    $changelogBody = $section.Value.Trim()
} else {
    $changelogBody = $changelog.Trim()
}

$stability = switch ($ReleaseType) {
    "release" { "stable" }
    "beta" { "beta" }
    "alpha" { "alpha" }
}

if (-not $ForeverPatch) {
    Write-Host "Fetching Wago game patches..." -ForegroundColor Cyan
    $game = Invoke-RestMethod -Uri "https://addons.wago.io/api/data/game" -Method Get
    if ($game.live_patches -and $game.live_patches.supported_forever_patches) {
        $ForeverPatch = [string]$game.live_patches.supported_forever_patches
    } elseif ($game.patches -and $game.patches.forever) {
        $ForeverPatch = @($game.patches.forever | Sort-Object)[-1]
    } else {
        $ForeverPatch = "1.60.1"
    }
}

$metadataObj = [ordered]@{
    label                       = "$Version-forever"
    stability                   = $stability
    changelog                   = $changelogBody
    supported_forever_patches   = @($ForeverPatch)
}
$metadata = $metadataObj | ConvertTo-Json -Compress

Write-Host ("Uploading {0} to Wago project {1} ({2}, forever {3})..." -f $ZipPath, $ProjectId, $stability, $ForeverPatch) -ForegroundColor Cyan

$headers = @{
    Authorization = "Bearer $ApiToken"
    Accept        = "application/json"
}
$form = @{
    metadata = $metadata
    file     = Get-Item -LiteralPath $ZipPath
}
$uploadUri = "https://addons.wago.io/api/projects/$ProjectId/version"

try {
    $response = Invoke-RestMethod -Uri $uploadUri -Headers $headers -Method Post -Form $form
} catch {
    $err = $_
    if ($err.ErrorDetails -and $err.ErrorDetails.Message) {
        Write-Host $err.ErrorDetails.Message -ForegroundColor Red
    }
    throw
}

Write-Host "Wago upload succeeded." -ForegroundColor Green
$response | ConvertTo-Json -Depth 6
Write-Host "Project: https://addons.wago.io/addons/$ProjectId"
