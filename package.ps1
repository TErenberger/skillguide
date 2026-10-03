<#
.SYNOPSIS
  Build a player-ready SkillGuide zip for manual CurseForge / Wago / WoWI upload.

.EXAMPLE
  .\package.ps1
  .\package.ps1 -Version 0.1.0
#>
[CmdletBinding()]
param(
    [string]$Version = "0.1.0",
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

if (-not $OutDir) {
    $OutDir = Join-Path $repoRoot "dist"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$stage = Join-Path $env:TEMP ("SkillGuide-package-" + [guid]::NewGuid().ToString("n"))
$addonRoot = Join-Path $stage "SkillGuide"
New-Item -ItemType Directory -Force -Path $addonRoot | Out-Null

$files = @(
    "SkillGuide.toc",
    "SkillGuide.lua",
    "LICENSE",
    "README.md",
    "CHANGELOG.md",
    "Core\Data.lua",
    "Core\Class.lua",
    "UI\MainFrame.lua"
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

# Replace packager version token for manual zips
$tocPath = Join-Path $addonRoot "SkillGuide.toc"
$toc = Get-Content $tocPath -Raw
$toc = $toc -replace "@project-version@", $Version
Set-Content -Path $tocPath -Value $toc -NoNewline -Encoding UTF8

$zipName = "SkillGuide-$Version.zip"
$zipPath = Join-Path $OutDir $zipName
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Compress-Archive -Path (Join-Path $stage "SkillGuide") -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item $stage -Recurse -Force

Write-Host "Created $zipPath" -ForegroundColor Green
Write-Host "Upload this zip to CurseForge / Wago / WoWInterface (Forever / interface 16001)."
Write-Host "Zip layout: SkillGuide\SkillGuide.toc + lua files"
