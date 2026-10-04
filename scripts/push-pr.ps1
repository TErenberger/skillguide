<#
.SYNOPSIS
  Push the current branch to origin and open (or create) a GitHub pull request.

.DESCRIPTION
  Intended for Cursor App Manager one-click actions. Uses gh.
  Does not create commits — push whatever is already committed on HEAD.

.EXAMPLE
  .\scripts\push-pr.ps1
  .\scripts\push-pr.ps1 -Base main -Title "Professions mode + skins"
  .\scripts\push-pr.ps1 -Draft
#>
[CmdletBinding()]
param(
    [string]$Base = "main",
    [string]$Title = "",
    [string]$Body = "",
    [switch]$Draft,
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $repoRoot

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) was not found on PATH. Install from https://cli.github.com/"
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git was not found on PATH."
}

$branch = (git branch --show-current).Trim()
if (-not $branch) {
    throw "Detached HEAD — check out a branch before opening a PR."
}
if ($branch -eq $Base) {
    throw "Current branch is '$Base'. Create/switch to a feature branch before opening a PR."
}

Write-Host "Pushing $branch -> origin ..." -ForegroundColor Cyan
git push -u origin HEAD
if ($LASTEXITCODE -ne 0) {
    throw "git push failed (exit $LASTEXITCODE)"
}

$existingUrl = $null
try {
    $existingUrl = (gh pr view --json url -q .url 2>$null)
} catch {
    $existingUrl = $null
}

if ($existingUrl) {
    Write-Host "PR already exists: $existingUrl" -ForegroundColor Green
    if (-not $NoBrowser) {
        gh pr view --web | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Start-Process $existingUrl
        }
    }
    Write-Output $existingUrl
    exit 0
}

if (-not $Title) {
    $Title = (git log -1 --pretty=%s).Trim()
    if (-not $Title) {
        $Title = $branch
    }
}

if (-not $Body) {
    $log = git log --oneline "$Base...HEAD" 2>$null
    if (-not $log) {
        $log = git log --oneline -10
    }
    $bullets = ($log | ForEach-Object { "- $_" }) -join "`n"
    $Body = @"
## Summary
$bullets

## Test plan
- [ ] `/reload` in Forever Classic
- [ ] Smoke-test `/sg` and `/pg`
"@
}

$ghArgs = @(
    "pr", "create",
    "--base", $Base,
    "--head", $branch,
    "--title", $Title,
    "--body", $Body
)
if ($Draft) {
    $ghArgs += "--draft"
}

Write-Host "Creating pull request against $Base ..." -ForegroundColor Cyan
$prUrl = & gh @ghArgs
if ($LASTEXITCODE -ne 0) {
    throw "gh pr create failed (exit $LASTEXITCODE)"
}

$prUrl = ($prUrl | Select-Object -Last 1).Trim()
Write-Host "Opened PR: $prUrl" -ForegroundColor Green

if (-not $NoBrowser -and $prUrl) {
    try {
        gh pr view --web | Out-Null
    } catch {
        Start-Process $prUrl
    }
}

Write-Output $prUrl
