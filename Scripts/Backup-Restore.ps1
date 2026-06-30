#Requires -RunAsAdministrator
<#
    Null OS - pre-apply rollback safety net.

    Runs FIRST and ALWAYS (ungated) in Configuration\main.yml. Creates a real
    recovery path before anything is modified:
      1. Enables System Restore on the system drive and removes the 24h throttle.
      2. Takes a named restore point ("Null OS Pre-Apply").
      3. Exports the registry hives Null OS touches to C:\NullOS-Backup\.

    Non-fatal: a failure here (e.g. System Restore disabled by policy, or a VM
    with no VSS) logs and continues - it must never abort the apply.

    Manual rollback:
      - Full:   System Restore -> "Null OS Pre-Apply".
      - Partial: import the .reg files in C:\NullOS-Backup\ and reboot.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$backup = "$env:SystemDrive\NullOS-Backup"

Write-Output "Null OS backup / restore-point stage"

# --- System Restore checkpoint --------------------------------------------
try {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
    # Bypass the once-per-24h restore point limit.
    New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' `
        -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force | Out-Null
    Checkpoint-Computer -Description 'Null OS Pre-Apply' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
    Write-Output "  -> restore point created"
} catch {
    Write-Output "  -> restore point skipped: $($_.Exception.Message)"
}

# --- Raw registry backups -------------------------------------------------
try {
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $exports = @{
        'services.reg'   = 'HKLM\SYSTEM\CurrentControlSet\Services'
        'pol-windows.reg'= 'HKLM\SOFTWARE\Policies\Microsoft\Windows'
        'datacoll.reg'   = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'
        'priority.reg'   = 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl'
        'multimedia.reg' = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia'
        'memmgmt.reg'    = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    }
    foreach ($name in $exports.Keys) {
        $out = Join-Path $backup $name
        & reg.exe export $exports[$name] $out /y | Out-Null
        Write-Output "  -> exported $($exports[$name]) => $out"
    }
    # Snapshot current BCD too.
    & bcdedit.exe /export (Join-Path $backup 'bcd.bak') | Out-Null
    Write-Output "  -> exported BCD => $backup\bcd.bak"
} catch {
    Write-Output "  -> registry backup error: $($_.Exception.Message)"
}

Write-Output "Backup stage complete. Recovery data in $backup"
exit 0
