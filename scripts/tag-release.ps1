<#
.SYNOPSIS
  Bump version, commit, and create an annotated release tag (optionally push).

.DESCRIPTION
  Thin App Manager wrapper around release.ps1.
  Pushing the tag triggers .github/workflows/release.yml (GH / CurseForge / Wago).

.EXAMPLE
  .\scripts\tag-release.ps1
  .\scripts\tag-release.ps1 -Bump minor -Push
  .\scripts\tag-release.ps1 -UpdateData -Bump patch -Push
  .\scripts\tag-release.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet("major", "minor", "patch", "none")]
    [string]$Bump = "patch",
    [switch]$UpdateData,
    [switch]$Push,
    [switch]$DryRun,
    [string]$Message = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$release = Join-Path $repoRoot "release.ps1"

$argsList = @{
    Bump = $Bump
}
if ($UpdateData) { $argsList.UpdateData = $true }
if ($Push) { $argsList.Push = $true }
if ($DryRun) { $argsList.DryRun = $true }
if ($Message) { $argsList.Message = $Message }

& $release @argsList
exit $LASTEXITCODE
