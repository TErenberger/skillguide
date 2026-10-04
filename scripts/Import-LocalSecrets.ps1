<#
.SYNOPSIS
  Load CF_API_KEY / WAGO_API_TOKEN (and friends) from a local .env if unset.

.DESCRIPTION
  Used by local publish scripts. Never commits secrets — keep them in `.env`
  (gitignored) or your user/process environment.
#>
[CmdletBinding()]
param(
    [string]$Path = ""
)

$ErrorActionPreference = "Stop"

if (-not $Path) {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $Path = Join-Path $repoRoot ".env"
}

if (-not (Test-Path -LiteralPath $Path)) {
    return
}

Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) {
        return
    }
    $eq = $line.IndexOf("=")
    if ($eq -lt 1) {
        return
    }
    $key = $line.Substring(0, $eq).Trim()
    $value = $line.Substring($eq + 1).Trim()
    if (
        ($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))
    ) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    $existing = [Environment]::GetEnvironmentVariable($key, "Process")
    if ([string]::IsNullOrEmpty($existing)) {
        Set-Item -Path "Env:$key" -Value $value
    }
}
