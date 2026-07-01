<#
    Null Control Center  (Mega-Plan P2 / F7)

    Post-install control for a Null OS machine. This is the answer to Revi OS's
    Revision Tool - and it goes one further: because the Null OS playbook takes a
    raw registry + BCD backup before applying, this tool can *restore from that
    backup*, which Revi cannot.

    Read-only STATUS works without elevation. Any -Action that changes state
    requires an elevated shell (the tool self-checks and refuses politely).

    USAGE
      Status (default):   .\NullControl.ps1
      Explicit:           .\NullControl.ps1 -Action status
      Re-enable things:   .\NullControl.ps1 -Action enable-defender
                          .\NullControl.ps1 -Action enable-update
                          .\NullControl.ps1 -Action enable-vbs
      Live re-debloat:    .\NullControl.ps1 -Action redebloat
      Restore backup:     .\NullControl.ps1 -Action restore-backup

    Windows PowerShell 5.1-safe. Reversible by design.
#>

[CmdletBinding()]
param(
    [ValidateSet('status','enable-defender','enable-update','enable-vbs','redebloat','restore-backup')]
    [string]$Action = 'status',

    [string]$BackupDir = "$env:SystemDrive\NullOS-Backup",

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Admin {
    if (-not (Test-Admin)) {
        Write-Host "This action changes system state and needs an elevated shell." -ForegroundColor Yellow
        Write-Host "Right-click PowerShell -> Run as administrator, then re-run." -ForegroundColor Yellow
        exit 1
    }
}

function Get-Reg($path, $name) {
    try { return (Get-ItemProperty -Path $path -Name $name -EA Stop).$name } catch { return $null }
}

function State($applied) {
    # Returns a colored label object for the dashboard.
    if ($applied) { return @{ text = 'APPLIED '; color = 'Cyan' } }
    return @{ text = 'stock   '; color = 'Gray' }
}

# ---------------------------------------------------------------------------
# DETECTION - which Null OS changes are currently live?
# ---------------------------------------------------------------------------
function Get-NullState {
    $s = [ordered]@{}

    # Telemetry
    $tel = Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
    $s['Telemetry disabled']    = ($tel -eq 0)

    # Defender realtime
    $defOff = $false
    $defPol = Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' 'DisableAntiSpyware'
    try { $mp = Get-MpComputerStatus -EA Stop; if (-not $mp.RealTimeProtectionEnabled) { $defOff = $true } } catch { }
    if ($defPol -eq 1) { $defOff = $true }
    $s['Defender disabled']     = $defOff

    # Windows Update service
    $wu = (Get-Service wuauserv -EA SilentlyContinue)
    $wuDisabled = $false
    if ($wu) { $wc = Get-CimInstance Win32_Service -Filter "Name='wuauserv'" -EA SilentlyContinue; if ($wc -and $wc.StartMode -eq 'Disabled') { $wuDisabled = $true } }
    $s['Windows Update disabled'] = $wuDisabled

    # Update pinning
    $pin = Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'TargetReleaseVersion'
    $s['Build pinned']          = ($pin -eq 1)

    # svchost grouping
    $svc = Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB'
    $s['svchost grouping']      = ($svc -eq 0xffffffff -or $svc -eq 4294967295)

    # VBS
    $vbs = Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity'
    $s['VBS disabled']          = ($vbs -eq 0)

    # Mitigations
    $mit = Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'FeatureSettingsOverride'
    $s['CPU mitigations off']   = ($mit -eq 3)

    # OneDrive (removed = APPLIED). Present binary/setup => not removed.
    $od = (Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe") -or (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe")
    $s['OneDrive removed']      = (-not $od)

    return $s
}

function Show-Status {
    $admin = Test-Admin
    Write-Host ""
    Write-Host "  N U L L   C O N T R O L   C E N T E R" -ForegroundColor Green
    Write-Host "  =====================================" -ForegroundColor DarkGray
    Write-Host ("  elevated: {0}    backup: {1}" -f $admin, (Test-Path $BackupDir))
    Write-Host ""

    # Live metrics (quick baseline echo)
    $procs = (Get-Process -EA SilentlyContinue).Count
    $os = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
    $ramGb = $null
    if ($os) { $ramGb = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory)/1MB, 2) }
    $svcRun = (Get-Service -EA SilentlyContinue | Where-Object { $_.Status -eq 'Running' }).Count
    $appx = (Get-AppxPackage -EA SilentlyContinue).Count
    Write-Host "  LIVE" -ForegroundColor White
    Write-Host ("    processes : {0}" -f $procs)
    Write-Host ("    RAM in use: {0} GB" -f $ramGb)
    Write-Host ("    services  : {0} running" -f $svcRun)
    Write-Host ("    appx      : {0}" -f $appx)
    Write-Host ""

    Write-Host "  NULL OS STATE" -ForegroundColor White
    $state = Get-NullState
    foreach ($k in $state.Keys) {
        $lbl = State $state[$k]
        Write-Host ("    [{0}] {1}" -f $lbl.text, $k) -ForegroundColor $lbl.color
    }
    Write-Host ""
    Write-Host "  ACTIONS  (run elevated)" -ForegroundColor White
    Write-Host "    -Action enable-defender   restore Defender realtime + policy"
    Write-Host "    -Action enable-update     restore Windows Update services + policy"
    Write-Host "    -Action enable-vbs        restore VBS / memory integrity"
    Write-Host "    -Action redebloat         re-run the live appx purge"
    Write-Host "    -Action restore-backup    reg/BCD restore from $BackupDir"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# ACTIONS
# ---------------------------------------------------------------------------
function Enable-Defender {
    Require-Admin
    Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' 'DisableAntiSpyware' -EA SilentlyContinue
    Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' 'DisableRealtimeMonitoring' -EA SilentlyContinue
    try { Set-MpPreference -DisableRealtimeMonitoring $false -EA Stop } catch { }
    Write-Host "Defender policy cleared. Reboot to fully restore realtime protection." -ForegroundColor Green
}

function Enable-Update {
    Require-Admin
    foreach ($svc in 'wuauserv','UsoSvc','WaaSMedicSvc') {
        try { Set-Service -Name $svc -StartupType Manual -EA Stop } catch { }
    }
    Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' -EA SilentlyContinue
    Write-Host "Windows Update services set to Manual, NoAutoUpdate cleared." -ForegroundColor Green
}

function Enable-Vbs {
    Require-Admin
    $dg = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
    if (Test-Path $dg) { New-ItemProperty $dg 'EnableVirtualizationBasedSecurity' -Value 1 -PropertyType DWord -Force | Out-Null }
    $hvci = "$dg\Scenarios\HypervisorEnforcedCodeIntegrity"
    if (-not (Test-Path $hvci)) { New-Item $hvci -Force | Out-Null }
    New-ItemProperty $hvci 'Enabled' -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Host "VBS / memory integrity re-enabled. Reboot required." -ForegroundColor Green
}

function Invoke-Redebloat {
    Require-Admin
    # The known-bloat family list, mirrored from Configuration\custom.yml. Live,
    # elevated re-purge fixes flaky over-existing-install applies.
    $fams = @(
        'Microsoft.BingNews','Microsoft.BingWeather','Microsoft.BingSearch','Microsoft.Microsoft3DViewer',
        'Microsoft.MicrosoftSolitaireCollection','Microsoft.MicrosoftOfficeHub','Microsoft.Office.OneNote',
        'Microsoft.People','microsoft.windowscommunicationsapps','Microsoft.SkypeApp','Microsoft.Getstarted',
        'Microsoft.GetHelp','Microsoft.WindowsFeedbackHub','Microsoft.MixedReality.Portal','Microsoft.WindowsMaps',
        'Microsoft.WindowsSoundRecorder','Microsoft.Todos','Microsoft.PowerAutomateDesktop','Microsoft.Windows.DevHome',
        'Microsoft.OutlookForWindows','MicrosoftTeams','MSTeams','Clipchamp.Clipchamp','Microsoft.549981C3F5F10',
        'Microsoft.Copilot','MicrosoftCorporationII.MicrosoftFamily','Microsoft.ZuneVideo','Microsoft.ZuneMusic',
        'Microsoft.MicrosoftJournal','MicrosoftCorporationII.QuickAssist','Microsoft.Windows.Ai.Copilot.Provider'
    )
    $removed = 0
    foreach ($f in $fams) {
        Get-AppxPackage -AllUsers "$f*" -EA SilentlyContinue | ForEach-Object {
            try { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -EA Stop; $removed++ } catch { }
        }
        Get-AppxProvisionedPackage -Online -EA SilentlyContinue |
            Where-Object { $_.DisplayName -like "$f*" } |
            ForEach-Object { try { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -EA Stop | Out-Null } catch { } }
    }
    Write-Host "Live re-debloat done. Packages removed this pass: $removed" -ForegroundColor Green
}

function Restore-Backup {
    Require-Admin
    if (-not (Test-Path $BackupDir)) { Write-Host "No backup found at $BackupDir" -ForegroundColor Red; exit 1 }
    Write-Host "This restores the raw registry + BCD captured before Null OS was applied." -ForegroundColor Yellow
    Write-Host "Source: $BackupDir" -ForegroundColor Yellow
    if (-not $Force) {
        $ans = Read-Host "Type RESTORE to proceed"
        if ($ans -ne 'RESTORE') { Write-Host "Aborted."; exit 1 }
    }
    $svc = Join-Path $BackupDir 'services.reg'
    $pol = Join-Path $BackupDir 'policies.reg'
    $bcd = Join-Path $BackupDir 'bcd.bak'
    if (Test-Path $svc) { & reg import $svc 2>$null; Write-Host "services.reg imported" }
    if (Test-Path $pol) { & reg import $pol 2>$null; Write-Host "policies.reg imported" }
    if (Test-Path $bcd) { & bcdedit /import $bcd 2>$null; Write-Host "BCD restored" }
    Write-Host "Restore complete. Reboot to finish. (A System Restore point 'Null OS Pre-Apply' also exists via rstrui.exe.)" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
switch ($Action) {
    'status'          { Show-Status }
    'enable-defender' { Enable-Defender }
    'enable-update'   { Enable-Update }
    'enable-vbs'      { Enable-Vbs }
    'redebloat'       { Invoke-Redebloat }
    'restore-backup'  { Restore-Backup }
}
