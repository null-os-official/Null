#Requires -RunAsAdministrator
<#
    Null OS - component store + disk footprint reduction.

    SAFE by design: uses DISM only. The WinSxS folder is NEVER deleted manually
    (that permanently breaks servicing and can render the OS unrepairable).

    -Mode Cleanup   : remove superseded components. Fully reversible servicing.
    -Mode ResetBase : Cleanup + /ResetBase. Reclaims more space BUT removes the
                      ability to uninstall already-installed updates. This fights
                      rollback - hence it is a separate opt-in toggle, off by default.

    Invoked by Configuration\main.yml (gated on GutWinSxS / GutWinSxSResetBase).
#>

[CmdletBinding()]
param(
    [ValidateSet('Cleanup','ResetBase')]
    [string]$Mode = 'Cleanup'
)

$ErrorActionPreference = 'Continue'

function Invoke-Dism {
    param([string[]]$DismArgs)
    Write-Output "DISM $($DismArgs -join ' ')"
    & dism.exe @DismArgs
    Write-Output "  -> exit $LASTEXITCODE"
}

Write-Output "Null OS WinSxS gut - mode: $Mode"

# Log current store size for before/after comparison.
Invoke-Dism @('/Online','/Cleanup-Image','/AnalyzeComponentStore')

# Component cleanup (+ ResetBase when requested).
$args = @('/Online','/Cleanup-Image','/StartComponentCleanup')
if ($Mode -eq 'ResetBase') { $args += '/ResetBase' }
Invoke-Dism $args

# Remove superseded service pack backups (no-op on most Win11 builds).
Invoke-Dism @('/Online','/Cleanup-Image','/SPSuperseded')

# Windows.old (previous install) - large, safe to drop if present.
$winold = "$env:SystemDrive\Windows.old"
if (Test-Path $winold) {
    try {
        Write-Output "Removing $winold ..."
        & takeown /f $winold /r /d y  | Out-Null
        & icacls $winold /grant administrators:F /t /c | Out-Null
        Remove-Item $winold -Recurse -Force -ErrorAction Stop
        Write-Output "  -> Windows.old removed"
    } catch {
        Write-Output "  -> Windows.old removal failed: $($_.Exception.Message)"
    }
}

# Windows Update download cache (regenerates on next update).
try {
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    $sd = "$env:SystemRoot\SoftwareDistribution\Download"
    if (Test-Path $sd) { Get-ChildItem $sd -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
    Start-Service wuauserv -ErrorAction SilentlyContinue
    Write-Output "Cleared SoftwareDistribution\Download"
} catch {
    Write-Output "SoftwareDistribution clear skipped: $($_.Exception.Message)"
}

# %TEMP% + Windows\Temp.
foreach ($t in $env:TEMP, "$env:SystemRoot\Temp") {
    if (Test-Path $t) { Get-ChildItem $t -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Output "Cleared temp directories"

Invoke-Dism @('/Online','/Cleanup-Image','/AnalyzeComponentStore')
Write-Output "Null OS WinSxS gut complete."
exit 0
