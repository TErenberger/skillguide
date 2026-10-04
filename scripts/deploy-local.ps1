<#
.SYNOPSIS
  Copy the current SkillGuideForever sources into the local WoW AddOns folder.

.EXAMPLE
  .\scripts\deploy-local.ps1
  .\scripts\deploy-local.ps1 -AddonsDir "D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\SkillGuideForever"
#>
[CmdletBinding()]
param(
    [string]$AddonsDir = "C:\Program Files\World of Warcraft\_classic_beta_\Interface\AddOns\SkillGuideForever"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $repoRoot

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

New-Item -ItemType Directory -Force -Path $AddonsDir | Out-Null

foreach ($rel in $files) {
    $src = Join-Path $repoRoot $rel
    if (-not (Test-Path $src)) {
        Write-Warning "Skipping missing file: $rel"
        continue
    }
    $dest = Join-Path $AddonsDir $rel
    $destParent = Split-Path -Parent $dest
    New-Item -ItemType Directory -Force -Path $destParent | Out-Null
    Copy-Item $src $dest -Force
}

Write-Host "Deployed SkillGuideForever -> $AddonsDir" -ForegroundColor Green
Write-Host "Reload the UI in-game with /reload" -ForegroundColor Cyan
