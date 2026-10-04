<#
.SYNOPSIS
  Build a player-ready SkillGuideForever zip for manual CurseForge / Wago / WoWI upload.

.EXAMPLE
  .\package.ps1
  .\package.ps1 -Version 0.1.0
#>
[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

if (-not $Version) {
    $toc = Get-Content (Join-Path $repoRoot "SkillGuideForever.toc") -Raw
    if ($toc -match '(?m)^##\s+Version:\s*(.+)$') {
        $Version = $Matches[1].Trim()
    }
}
if (-not $Version) {
    throw "Could not determine version (pass -Version or set ## Version in TOC)."
}

if (-not $OutDir) {
    $OutDir = Join-Path $repoRoot "dist"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$stage = Join-Path $env:TEMP ("SkillGuideForever-package-" + [guid]::NewGuid().ToString("n"))
$addonRoot = Join-Path $stage "SkillGuideForever"
New-Item -ItemType Directory -Force -Path $addonRoot | Out-Null

$files = @(
    "SkillGuideForever.toc",
    "SkillGuideForever.lua",
    "LICENSE",
    "README.md",
    "CHANGELOG.md",
    "Core\Data.lua",
    "Core\ProfessionData.lua",
    "Core\Class.lua",
    "Core\Profession.lua",
    "Core\Integration.lua",
    "UI\MainFrame.lua",
    "UI\ProfessionFrame.lua",
    "UI\Skins.lua",
    "UI\Options.lua",
    "docs\INTEGRATION.md"
)

foreach ($rel in $files) {
    $src = Join-Path $repoRoot $rel
    if (-not (Test-Path $src)) {
        throw "Missing file: $rel"
    }
    $dest = Join-Path $addonRoot $rel
    $destParent = Split-Path -Parent $dest
    New-Item -ItemType Directory -Force -Path $destParent | Out-Null
    Copy-Item $src $dest -Force
}

$zipName = "SkillGuideForever-$Version.zip"
$zipPath = Join-Path $OutDir $zipName
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Compress-Archive -Path (Join-Path $stage "SkillGuideForever") -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item $stage -Recurse -Force

Write-Host "Created $zipPath" -ForegroundColor Green
Write-Host "Upload this zip to CurseForge / Wago / WoWInterface (Forever / interface 16001)."
Write-Host "Zip layout: SkillGuideForever\SkillGuideForever.toc + lua files"
