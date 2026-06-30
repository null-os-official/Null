<#
    Null OS - playbook builder.

    Packages the repository into a single .apbx for AME Wizard Beta.
    The .apbx is a 7-Zip archive with AES-256 + encrypted headers (-mhe=on),
    password "malte" (the fixed password AME Wizard expects for beta playbooks).

    Usage:
        .\build.ps1                       # -> dist\NullOS-<version>.apbx
        .\build.ps1 -OutDir release       # custom output directory
        .\build.ps1 -SevenZip "C:\7z\7za.exe"
#>

[CmdletBinding()]
param(
    [string]$OutDir   = 'dist',
    [string]$SevenZip,
    [string]$Password = 'malte'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $root

# --- Locate a 7-Zip CLI ----------------------------------------------------
function Find-SevenZip {
    param([string]$Explicit)
    if ($Explicit) {
        if (Test-Path $Explicit) { return $Explicit }
        throw "7-Zip not found at supplied path: $Explicit"
    }
    foreach ($c in 'tools\7za.exe','7z','7za') {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    foreach ($p in @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    )) { if (Test-Path $p) { return $p } }
    throw "7-Zip CLI not found. Install 7-Zip, add 7z/7za to PATH, drop 7za.exe in .\tools\, or pass -SevenZip."
}

$sevenZip = Find-SevenZip -Explicit $SevenZip
Write-Host "[*] 7-Zip: $sevenZip"

# --- Read version + name from playbook.conf --------------------------------
if (-not (Test-Path 'playbook.conf')) { throw "playbook.conf missing - run from the repo root." }
[xml]$conf  = Get-Content 'playbook.conf' -Raw
$version    = $conf.Playbook.Version
if (-not $version) { $version = '0.0.0' }

# --- Verify the required payload exists (guard against orphaned builds) -----
$required = @(
    'playbook.conf'
    'Configuration\main.yml'
    'Configuration\Telemetry.reg'
    'Configuration\Privacy.reg'
    'Configuration\Services.reg'
    'Configuration\VisualFX.reg'
    'Scripts\Backup-Restore.ps1'
    'Scripts\RemoveBloatware.ps1'
    'Scripts\OptimizeLatency.ps1'
    'Scripts\GutWinSxS.ps1'
    'Scripts\KernelTweaks.ps1'
)
$missing = $required | Where-Object { -not (Test-Path $_) }
if ($missing) { throw "Refusing to build - missing required files:`n  $($missing -join "`n  ")" }
Write-Host "[*] Payload verified ($($required.Count) required files present)."

# --- Output path -----------------------------------------------------------
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$apbx = Join-Path $OutDir "NullOS-$version.apbx"
if (Test-Path $apbx) { Remove-Item $apbx -Force }

# --- Things that must NEVER go in the shipped playbook ----------------------
$exclude = @(
    '-xr!.git'
    '-xr!.github'
    '-xr!docs'
    '-xr!dist'
    '-xr!release'
    '-xr!tools'
    '-x!build.ps1'
    '-x!README.md'
    '-xr!*.original.md'
)

# --- Pack ------------------------------------------------------------------
# -t7z AES-256, -mhe=on encrypts the file listing too, -mx=9 max compression.
$args = @(
    'a','-t7z',$apbx,'*',
    "-p$Password",'-mhe=on','-mx=9','-bso0','-bsp0'
) + $exclude

Write-Host "[*] Packing -> $apbx"
& $sevenZip @args
if ($LASTEXITCODE -ne 0) { throw "7-Zip exited with code $LASTEXITCODE" }

# --- Report ----------------------------------------------------------------
$item = Get-Item $apbx
$sha  = (Get-FileHash $apbx -Algorithm SHA256).Hash
$sizeMB = [math]::Round($item.Length / 1MB, 2)

Write-Host ""
Write-Host "  Null OS playbook built" -ForegroundColor Green
Write-Host "  ----------------------"
Write-Host "  file    : $($item.FullName)"
Write-Host "  version : $version"
Write-Host "  size    : $sizeMB MB"
Write-Host "  sha256  : $sha"
Write-Host "  password: $Password"
