<#
.SYNOPSIS
  Package SkillGuideForever and upload to CurseForge and/or Wago (local).

.DESCRIPTION
  App Manager / local alternative to the GitHub Actions BigWigs packager upload
  step. Reads ## Version / project ids from the TOC. Tokens come from the
  process environment or a gitignored `.env` file:
    CF_API_KEY=...
    WAGO_API_TOKEN=...

.EXAMPLE
  .\scripts\publish-local.ps1
  .\scripts\publish-local.ps1 -CurseForgeOnly
  .\scripts\publish-local.ps1 -WagoOnly -ReleaseType beta
  .\scripts\publish-local.ps1 -SkipPackage -Version 0.4.0
#>
[CmdletBinding()]
param(
    [string]$Version = "",
    [ValidateSet("alpha", "beta", "release")]
    [string]$ReleaseType = "release",
    [switch]$SkipPackage,
    [switch]$CurseForgeOnly,
    [switch]$WagoOnly,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $repoRoot

& (Join-Path $repoRoot "scripts\Import-LocalSecrets.ps1")

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
    throw "Could not read ## Version from SkillGuideForever.toc"
}

$doCf = -not $WagoOnly
$doWago = -not $CurseForgeOnly
$curseId = Get-TocField "X-Curse-Project-ID"
$wagoId = Get-TocField "X-Wago-ID"

Write-Host "SkillGuide Forever local publish" -ForegroundColor Cyan
Write-Host "  version : $Version"
Write-Host "  type    : $ReleaseType"
Write-Host "  package : $(-not $SkipPackage)"
Write-Host "  CF      : $doCf $(if ($curseId) { "($curseId)" } else { "(no TOC id)" })"
Write-Host "  Wago    : $doWago $(if ($wagoId) { "($wagoId)" } else { "(no TOC id)" })"
Write-Host "  dry-run : $DryRun"
Write-Host ""

if ($DryRun) {
    Write-Host "Dry run complete (no package/upload)." -ForegroundColor Green
    exit 0
}

if (-not $SkipPackage) {
    Write-Host "Packaging..." -ForegroundColor Cyan
    & (Join-Path $repoRoot "package.ps1") -Version $Version
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "package.ps1 failed (exit $LASTEXITCODE)"
    }
}

$zipPath = Join-Path $repoRoot "dist\SkillGuideForever-$Version.zip"
if (-not (Test-Path -LiteralPath $zipPath)) {
    throw "Zip missing after package: $zipPath"
}

$errors = @()

if ($doCf) {
    if (-not $curseId) {
        Write-Host "Skipping CurseForge (no ## X-Curse-Project-ID)." -ForegroundColor Yellow
    } elseif (-not $env:CF_API_KEY) {
        Write-Host "Skipping CurseForge (CF_API_KEY not set)." -ForegroundColor Yellow
    } else {
        try {
            & (Join-Path $repoRoot "upload-curseforge.ps1") -Version $Version -ReleaseType $ReleaseType -ZipPath $zipPath
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
                throw "upload-curseforge.ps1 exit $LASTEXITCODE"
            }
        } catch {
            $errors += "CurseForge: $($_.Exception.Message)"
            Write-Host "CurseForge upload failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

if ($doWago) {
    if (-not $wagoId) {
        Write-Host "Skipping Wago (no ## X-Wago-ID)." -ForegroundColor Yellow
    } elseif (-not $env:WAGO_API_TOKEN) {
        Write-Host "Skipping Wago (WAGO_API_TOKEN not set)." -ForegroundColor Yellow
    } else {
        try {
            & (Join-Path $repoRoot "upload-wago.ps1") -Version $Version -ReleaseType $ReleaseType -ZipPath $zipPath
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
                throw "upload-wago.ps1 exit $LASTEXITCODE"
            }
        } catch {
            $errors += "Wago: $($_.Exception.Message)"
            Write-Host "Wago upload failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host ""
if ($errors.Count -gt 0) {
    Write-Host "Finished with errors:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "Local publish complete." -ForegroundColor Green
Write-Host "  CurseForge: https://www.curseforge.com/wow/addons/skillguideforever/files"
if ($wagoId) {
    Write-Host "  Wago:       https://addons.wago.io/addons/$wagoId"
}
