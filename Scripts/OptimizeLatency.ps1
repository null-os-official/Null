#Requires -RunAsAdministrator
<#
    Null OS - latency & responsiveness tuning.

    -Profile Balanced : safe on laptops / battery. Network stack, scheduler,
                        MMCSS gaming priorities, high-performance power plan.
    -Profile Extreme  : everything in Balanced PLUS power-saving kills and
                        DisablePagingExecutive. Desktop / plugged-in only.

    Nothing here touches Explorer, audio endpoints, NIC drivers, or GPU drivers.
    HPET / bcdedit clock surgery is deliberately omitted - it is hardware
    dependent and a common cause of boot/stability regressions.

    Invoked by Configuration\main.yml (gated on the latency radio option).
#>

[CmdletBinding()]
param(
    [ValidateSet('Balanced','Extreme')]
    [string]$Profile = 'Balanced'
)

$ErrorActionPreference = 'Continue'

function Set-Reg {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$Type = 'DWord'
    )
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-Output "set  $Path\$Name = $Value"
    } catch {
        Write-Output "FAIL $Path\$Name -> $($_.Exception.Message)"
    }
}

Write-Output "Null OS latency tuning - profile: $Profile"

# === CPU scheduler: bias quantum/boost toward the foreground app =============
# 0x26 (38) = short, fixed-length quantums with a 3:1 foreground boost.
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38

# === Network stack ==========================================================
# Kill network throttling (caps non-multimedia traffic to ~10pkt/ms by default).
Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 0xffffffff

# MMCSS responsiveness. 10 keeps audio (MMCSS) safe; Extreme pushes to 0.
$responsiveness = if ($Profile -eq 'Extreme') { 0 } else { 10 }
Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' $responsiveness

# MMCSS "Games" task scheduling category - prioritise game threads / GPU.
$games = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
Set-Reg $games 'GPU Priority' 8
Set-Reg $games 'Priority' 6
Set-Reg $games 'Scheduling Category' 'High' 'String'
Set-Reg $games 'SFIO Priority' 'High' 'String'

# Nagle's algorithm + delayed ACK off on every IPv4 interface (lower ping jitter).
$ifRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
if (Test-Path $ifRoot) {
    Get-ChildItem $ifRoot | ForEach-Object {
        Set-Reg $_.PSPath 'TcpAckFrequency' 1
        Set-Reg $_.PSPath 'TCPNoDelay' 1
        Set-Reg $_.PSPath 'TcpDelAckTicks' 0
    }
}

# MSMQ Nagle off (only if MSMQ present; harmless key otherwise).
Set-Reg 'HKLM:\SOFTWARE\Microsoft\MSMQ\Parameters' 'TCPNoDelay' 1

# === Input ==================================================================
# Disable "Enhance pointer precision" (mouse acceleration) for consistent aim.
Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'
Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'

# === Power plan =============================================================
# High Performance active; Extreme switches on the hidden Ultimate plan.
try {
    if ($Profile -eq 'Extreme') {
        # Duplicate Ultimate Performance (no-op if it already exists), then activate.
        $dup = powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
        $guid = ($dup | Select-String -Pattern '([0-9a-fA-F-]{36})').Matches.Value
        if ($guid) { powercfg /setactive $guid } else { powercfg /setactive SCHEME_MIN }
    } else {
        powercfg /setactive SCHEME_MIN   # High performance
    }
    Write-Output "power plan applied ($Profile)"
} catch {
    Write-Output "FAIL power plan -> $($_.Exception.Message)"
}

# === Extreme-only: power saving kills + kernel paging =======================
if ($Profile -eq 'Extreme') {
    # Keep the kernel + drivers resident in RAM (no paging to disk).
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive' 1

    # USB selective suspend off (AC + DC) - removes USB device wake latency.
    powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
    powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null

    # Processor minimum state 100% (AC) - no downclock under interrupt load.
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 2>$null

    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Output "extreme power tuning applied"
}

Write-Output "Null OS latency tuning complete."
exit 0
