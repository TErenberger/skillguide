<#
.SYNOPSIS
  Refresh SkillGuide Forever skill data from Wowhead and optionally deploy it.

.EXAMPLE
  .\update-data.ps1
  .\update-data.ps1 -Deploy
  .\update-data.ps1 -Deploy -Class hunter
  .\update-data.ps1 -FromCache -Deploy
#>
[CmdletBinding()]
param(
    [switch]$Deploy,
    [switch]$FromCache,
    [switch]$DryRun,
    [ValidateSet("warrior","paladin","hunter","rogue","priest","shaman","mage","warlock","druid")]
    [string[]]$Class,
    [string]$AddonsDir = "C:\Program Files\World of Warcraft\_classic_beta_\Interface\AddOns\SkillGuide"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command py -ErrorAction SilentlyContinue
}
if (-not $python) {
    Write-Error "Python was not found on PATH. Install Python 3, then re-run."
}

$argsList = @("tools\extract_wowhead.py")
if ($Deploy) { $argsList += "--deploy" }
if ($FromCache) { $argsList += "--from-cache" }
if ($DryRun) { $argsList += "--dry-run" }
if ($AddonsDir) { $argsList += @("--addons-dir", $AddonsDir) }
foreach ($c in $Class) {
    $argsList += @("--class", $c)
}

Write-Host "Running: $($python.Source) $($argsList -join ' ')" -ForegroundColor Cyan
& $python.Source @argsList
exit $LASTEXITCODE
