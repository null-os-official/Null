#Requires -RunAsAdministrator
<#
    Null OS - performance, latency and responsiveness engine.

    -Profile Balanced : safe on laptops / battery. Network stack, scheduler,
                        MMCSS, service-host de-splitting, NTFS, FTH, background
                        apps, fast-startup off, high-performance power plan.
    -Profile Extreme  : everything in Balanced PLUS the full low-latency power
                        scheme (NVMe/USB/throttle/device power-saving disabled),
                        DisablePagingExecutive. Desktop / plugged-in only.

    Nothing here touches Explorer, audio endpoints, NIC drivers, or GPU drivers.
    HPET / bcdedit clock surgery lives in KernelTweaks.ps1, deliberately separate.
#>

[CmdletBinding()]
param(
    [ValidateSet('Balanced','Extreme')]
    [string]$Profile = 'Balanced'
)

$ErrorActionPreference = 'Continue'

function Set-Reg {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name,
          [Parameter(Mandatory)]$Value,[string]$Type='DWord')
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-Output "set  $Path\$Name = $Value"
    } catch { Write-Output "FAIL $Path\$Name -> $($_.Exception.Message)" }
}

Write-Output "Null OS performance engine - profile: $Profile"

# === CPU scheduler: bias quantum/boost to the foreground app =================
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38

# === Network stack ==========================================================
Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 0xffffffff
$responsiveness = if ($Profile -eq 'Extreme') { 0 } else { 10 }
Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' $responsiveness

$games = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
Set-Reg $games 'GPU Priority' 8
Set-Reg $games 'Priority' 6
Set-Reg $games 'Scheduling Category' 'High' 'String'
Set-Reg $games 'SFIO Priority' 'High' 'String'

# Nagle + delayed ACK off on every IPv4 interface.
$ifRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
if (Test-Path $ifRoot) {
    Get-ChildItem $ifRoot | ForEach-Object {
        Set-Reg $_.PSPath 'TcpAckFrequency' 1
        Set-Reg $_.PSPath 'TCPNoDelay' 1
        Set-Reg $_.PSPath 'TcpDelAckTicks' 0
    }
}
Set-Reg 'HKLM:\SOFTWARE\Microsoft\MSMQ\Parameters' 'TCPNoDelay' 1

# === Input: mouse acceleration off ==========================================
Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'
Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'

# === Service Host de-splitting ==============================================
# Merges svchost groups -> large drop in idle process count and RAM. Xbox
# service groups are excluded so Game Bar / Game Pass keep working.
Write-Output 'De-splitting service hosts (lower process count / RAM)...'
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' |
    Where-Object { $_.Name -notmatch 'Xbl|Xbox' } |
    ForEach-Object {
        if ($null -ne (Get-ItemProperty -Path "Registry::$_" -ErrorAction SilentlyContinue).Start) {
            Set-ItemProperty -Path "Registry::$_" -Name 'SvcHostSplitDisable' -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue
        }
    }

# === NTFS: drop last-access + 8.3 name generation ===========================
& fsutil behavior set disablelastaccess 1 | Out-Null
& fsutil 8dot3name set 1 | Out-Null
Write-Output 'NTFS: disablelastaccess + 8dot3 disabled'

# === Fault Tolerant Heap off (removes the per-app crash perf penalty) =======
if ([Environment]::Is64BitOperatingSystem) {
    & rundll32.exe fthsvc.dll,FthSysprepSpecialize 2>$null
}
Set-Reg 'HKLM:\SOFTWARE\Microsoft\FTH' 'Enabled' 0

# === Background apps off ====================================================
Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0

# === Fast startup off (clean boot, NTFS accessible offline) =================
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0

# === Power throttling + storage idle off ====================================
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Storage' 'StorageD3InModernStandby' 0

# === Automatic maintenance: keep it (TRIM/defrag) but stop it waking the box =
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Task Scheduler\Maintenance' 'WakeUp' 0

# === Power plan =============================================================
try {
    if ($Profile -eq 'Extreme') {
        $guid = '11111111-1111-1111-1111-111111111111'
        if (-not (powercfg /l | Select-String $guid -Quiet)) {
            powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 $guid | Out-Null
        }
        powercfg /setactive $guid
        powercfg /changename $guid 'Null OS' 'Lowest-latency, no power saving.'
        # NVMe idle timeouts -> 0
        powercfg /setacvalueindex $guid 0012ee47-9041-4b5d-9b77-535fba8b1442 d3d55efd-c1ff-424e-9dc3-441be7833010 0
        powercfg /setacvalueindex $guid 0012ee47-9041-4b5d-9b77-535fba8b1442 d639518a-e56d-4345-8af2-b9f32fb26109 0
        powercfg /setacvalueindex $guid 0012ee47-9041-4b5d-9b77-535fba8b1442 fc7372b6-ab2d-43ee-8797-15e9841f2cca 0
        # USB selective suspend + USB3 link power off
        powercfg /setacvalueindex $guid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
        powercfg /setacvalueindex $guid 2a737441-1930-4402-8d77-b2bebba308a3 d4e98f31-5ffe-4ce1-be31-1b38b384c009 0
        # Allow throttle states off
        powercfg /setacvalueindex $guid 54533251-82be-4824-96c1-47b60b740d00 3b04d4fd-1cc7-4f23-ab1c-d1337819c4bb 0
        # Processor min state 100%, perf time-check 200ms (fewer DPCs)
        powercfg /setacvalueindex $guid 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c 100
        powercfg /setacvalueindex $guid 54533251-82be-4824-96c1-47b60b740d00 4d2b0152-7d5c-498b-88e2-34345392a2c5 200
        powercfg /setactive $guid

        # NIC power-saving off (EEE / green ethernet / selective suspend)
        try {
            $props = Get-NetAdapter -Physical -ErrorAction Stop | Get-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue
            foreach ($kw in 'EEE','EnableGreenEthernet','EeePhyEnable','ULPMode','EnablePowerManagement','SelectiveSuspend','PowerSavingMode','AutoPowerSaveModeEnabled') {
                $props | Where-Object { $_.RegistryKeyword -eq "*$kw" -or $_.RegistryKeyword -eq $kw } |
                    Set-NetAdapterAdvancedProperty -RegistryValue 0 -ErrorAction SilentlyContinue
            }
        } catch { Write-Output "NIC power-saving skipped: $($_.Exception.Message)" }

        # NVMe driver: never enter low-power
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device' 'IdlePowerMode' 0
        # Keep kernel resident; no page combining
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive' 1
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePageCombining' 1
        Write-Output 'Extreme power scheme applied'
    } else {
        powercfg /setactive SCHEME_MIN   # High performance
        Write-Output 'High-performance power plan active'
    }
} catch { Write-Output "FAIL power plan -> $($_.Exception.Message)" }

Write-Output 'Null OS performance engine complete.'
exit 0
