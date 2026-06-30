#Requires -RunAsAdministrator
<#
    Null OS - kernel / boot latency tuning.

    BCD philosophy (important): on modern CPUs with an invariant TSC, FORCING the
    HPET via `useplatformclock true` INCREASES latency and causes stutter. The
    correct "HPET tuning" is the opposite - let Windows use the TSC, kill the
    dynamic tick, and enforce enhanced TSC sync. So this script deletes any forced
    platform clock rather than setting one.

    -DisableMitigations : turns OFF Spectre/Meltdown speculative-execution
                          mitigations and VBS/HVCI for raw gaming throughput.
                          This LOWERS security. Off by default; opt-in only.

    Revert (manual):
      bcdedit /deletevalue disabledynamictick
      bcdedit /deletevalue tscsyncpolicy
      reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v FeatureSettingsOverride /f

    Invoked by Configuration\main.yml.
#>

[CmdletBinding()]
param(
    [switch]$DisableMitigations
)

$ErrorActionPreference = 'Continue'

function Set-Bcd {
    param([string]$Args)
    Write-Output "bcdedit $Args"
    Start-Process -FilePath bcdedit.exe -ArgumentList $Args -Wait -NoNewWindow
}

function Set-Reg {
    param([string]$Path,[string]$Name,$Value,[string]$Type='DWord')
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-Output "set  $Path\$Name = $Value"
    } catch { Write-Output "FAIL $Path\$Name -> $($_.Exception.Message)" }
}

Write-Output "Null OS kernel tweaks (DisableMitigations=$DisableMitigations)"

# === BCD: timer / clock ====================================================
# Kill the periodic dynamic tick -> fewer timer interrupts -> lower DPC latency.
Set-Bcd 'AdvancedOptions /set {current} disabledynamictick yes'
Set-Bcd '/set disabledynamictick yes'
# Enhanced TSC synchronization across cores.
Set-Bcd '/set tscsyncpolicy Enhanced'
# Remove any FORCED platform clock (HPET) - TSC is lower latency on modern CPUs.
Set-Bcd '/deletevalue useplatformclock'
Set-Bcd '/deletevalue useplatformtick'

# === Kernel timer distribution =============================================
# Spread timer expirations across logical processors (smoother DPC profile).
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'DistributeTimers' 1
# Global timer resolution request flag (let multimedia apps raise it).
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1

# === Optional: speculative-execution mitigations + VBS off (gaming) =========
if ($DisableMitigations) {
    Write-Output "WARNING: disabling CPU mitigations and VBS/HVCI - reduces security."
    $mm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    Set-Reg $mm 'FeatureSettingsOverride' 1
    Set-Reg $mm 'FeatureSettingsOverrideMask' 3

    $dg = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
    Set-Reg $dg 'EnableVirtualizationBasedSecurity' 0
    Set-Reg "$dg\Scenarios\HypervisorEnforcedCodeIntegrity" 'Enabled' 0
}

Write-Output "Null OS kernel tweaks complete. Reboot required for BCD changes."
exit 0
