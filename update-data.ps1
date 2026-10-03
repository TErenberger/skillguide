<#
.SYNOPSIS
  Refresh SkillGuideForever Forever skill data from Wowhead and optionally deploy it.

.EXAMPLE
  .\update-data.ps1
  .\update-data.ps1 -Deploy
  .\update-data.ps1 -Deploy -Class hunter
  .\update-data.ps1 -ProfessionsOnly -Deploy
  .\update-data.ps1 -Profession alchemy,cooking -Deploy
  .\update-data.ps1 -FromCache -Deploy
#>
[CmdletBinding()]
param(
    [switch]$Deploy,
    [switch]$FromCache,
    [switch]$DryRun,
    [switch]$ClassesOnly,
    [switch]$ProfessionsOnly,
    [ValidateSet("warrior","paladin","hunter","rogue","priest","shaman","mage","warlock","druid")]
    [string[]]$Class,
    [ValidateSet(
        "alchemy","blacksmithing","enchanting","engineering","herbalism",
        "leatherworking","mining","skinning","tailoring","cooking","first-aid","fishing"
    )]
    [string[]]$Profession,
    [string]$AddonsDir = "C:\Program Files\World of Warcraft\_classic_beta_\Interface\AddOns\SkillGuideForever"
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
if ($ClassesOnly) { $argsList += "--classes-only" }
if ($ProfessionsOnly) { $argsList += "--professions-only" }
if ($AddonsDir) { $argsList += @("--addons-dir", $AddonsDir) }
foreach ($c in $Class) {
    $argsList += @("--class", $c)
}
foreach ($p in $Profession) {
    $argsList += @("--profession", $p)
}

Write-Host "Running: $($python.Source) $($argsList -join ' ')" -ForegroundColor Cyan
& $python.Source @argsList
exit $LASTEXITCODE
