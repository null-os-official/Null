<#
    Null OS - Baseline Harness  (Mega-Plan P0 / F1)

    Captures a reproducible performance snapshot of a Windows install so every
    Null OS claim ships with a receipt. Run it on a CLEAN Win11 VM before apply,
    again after apply, then diff the two. A claim without a matching report is
    not allowed to ship.

    Metrics captured:
      - Idle process count
      - Physical RAM in use (headline "idle RAM") + commit charge (best-effort)
      - Boot time (MainPathBootTime from the Diagnostics-Performance log; falls
        back to uptime since LastBootUpTime)
      - DPC/ISR latency (best-effort: uses xperf if the Windows Perf Toolkit is
        present; otherwise records "skipped - tool absent" honestly)
      - Installed appx count (current user + all users if elevated)
      - Service counts (running / auto-start / total)
      - Full system context (build, model, CPU, RAM, VM detection, admin state)

    Windows PowerShell 5.1-safe (no ternary, no ??, no if-as-expression).

    USAGE
      Capture:   .\Measure-Baseline.ps1 -Profile clean-vm -Label before
                 .\Measure-Baseline.ps1 -Profile clean-vm -Label after
      Compare:   .\Measure-Baseline.ps1 -Compare .\reports\<before>.json,.\reports\<after>.json
                 (comma-separated: it is a single array parameter)

    Output: reports\<build>-<profile>-<label>-<timestamp>.{json,md}
#>

[CmdletBinding(DefaultParameterSetName = 'Capture')]
param(
    [Parameter(ParameterSetName = 'Capture')]
    [string]$Profile = 'unspecified',

    [Parameter(ParameterSetName = 'Capture')]
    [ValidateNotNullOrEmpty()]
    [string]$Label = 'snapshot',

    [Parameter(ParameterSetName = 'Capture')]
    [int]$SettleSeconds = 0,

    [Parameter(ParameterSetName = 'Compare')]
    [string[]]$Compare,

    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $OutDir) { $OutDir = Join-Path $root 'reports' }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SystemContext {
    $os = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -EA SilentlyContinue | Select-Object -First 1
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA SilentlyContinue

    $model = ''
    $manu  = ''
    if ($cs) { $model = "$($cs.Model)"; $manu = "$($cs.Manufacturer)" }
    $isVm = $false
    if (($model -match 'Virtual|VMware|KVM|VirtualBox|Hyper-V|QEMU') -or ($manu -match 'VMware|innotek|QEMU|Microsoft Corporation.*Virtual')) { $isVm = $true }

    $totalGb = 0
    if ($os) { $totalGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2) }  # KB -> GB

    # Win11 still reports ProductName "Windows 10 Pro" in the registry (known quirk).
    # Build >= 22000 is Windows 11 - correct the label so the report tells the truth.
    $edition = "$($cv.ProductName)"
    $buildInt = 0
    [int]::TryParse("$($cv.CurrentBuildNumber)", [ref]$buildInt) | Out-Null
    if ($buildInt -ge 22000 -and $edition -match 'Windows 10') {
        $edition = $edition -replace 'Windows 10', 'Windows 11'
    }

    return [ordered]@{
        capturedUtc   = (Get-Date).ToUniversalTime().ToString('o')
        hostname      = $env:COMPUTERNAME
        elevated      = (Test-Admin)
        displayVersion= "$($cv.DisplayVersion)"
        buildNumber   = "$($cv.CurrentBuildNumber).$($cv.UBR)"
        edition       = $edition
        manufacturer  = $manu
        model         = $model
        isVirtualMachine = $isVm
        cpu           = "$($cpu.Name)".Trim()
        logicalCpus   = [int]$cs.NumberOfLogicalProcessors
        totalRamGb    = $totalGb
    }
}

function Get-ProcessCount {
    return (Get-Process -EA SilentlyContinue).Count
}

function Get-RamInUseGb {
    # Physical RAM in use = total visible - free physical. KB -> GB. Locale-safe.
    $os = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
    if (-not $os) { return $null }
    $usedKb = $os.TotalVisibleMemorySize - $os.FreePhysicalMemory
    return [math]::Round($usedKb / 1MB, 3)
}

function Get-CommitChargeGb {
    # Best-effort commit charge. Perf counter path is localized; fall back to CIM.
    try {
        $c = Get-Counter '\Memory\Committed Bytes' -EA Stop
        return [math]::Round($c.CounterSamples[0].CookedValue / 1GB, 3)
    } catch {
        $os = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
        if (-not $os) { return $null }
        $usedKb = $os.TotalVirtualMemorySize - $os.FreeVirtualMemory
        return [math]::Round($usedKb / 1MB, 3)
    }
}

function Get-BootTimeMs {
    # Preferred: MainPathBootTime from the Diagnostics-Performance operational log.
    try {
        $ev = Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' `
              -FilterXPath "*[System[(EventID=100)]]" -MaxEvents 1 -EA Stop
        [xml]$x = $ev.ToXml()
        $node = $x.Event.EventData.Data | Where-Object { $_.Name -eq 'MainPathBootTime' }
        if ($node -and $node.'#text') {
            return [pscustomobject]@{ ms = [int]$node.'#text'; source = 'Diagnostics-Performance/100 MainPathBootTime' }
        }
    } catch { }
    # Fallback: not a boot duration, just uptime since last boot (flagged as such).
    $os = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
    if ($os) {
        $up = (Get-Date) - $os.LastBootUpTime
        return [pscustomobject]@{ ms = $null; source = "fallback: uptime only ($([math]::Round($up.TotalMinutes,1)) min since LastBootUpTime); enable the Diagnostics-Performance log for real boot timing" }
    }
    return [pscustomobject]@{ ms = $null; source = 'unavailable' }
}

function Get-DpcLatency {
    # DPC/ISR latency needs kernel tracing. xperf (Windows Perf Toolkit / ADK) is
    # the honest CLI path; it is not installed by default. Detect and use if
    # present, otherwise record skipped - never fabricate a number.
    $xperf = Get-Command xperf.exe -EA SilentlyContinue
    if (-not $xperf) {
        return [ordered]@{ status = 'skipped'; reason = 'xperf.exe not found (install Windows Performance Toolkit from the Windows ADK to capture DPC/ISR latency)'; maxDpcUs = $null }
    }
    if (-not (Test-Admin)) {
        return [ordered]@{ status = 'skipped'; reason = 'xperf present but not elevated - re-run as admin to capture DPC/ISR'; maxDpcUs = $null }
    }
    # Present + elevated: capture a short kernel trace and summarize DPCs.
    $etl = Join-Path $env:TEMP ("nullos-dpc-{0}.etl" -f ([guid]::NewGuid().ToString('N')))
    try {
        & $xperf.Source -on PROC_THREAD+LOADER+DPC+INTERRUPT -f $etl 2>$null | Out-Null
        Start-Sleep -Seconds 10
        & $xperf.Source -stop 2>$null | Out-Null
        $summary = & $xperf.Source -i $etl -a dpcisr 2>$null
        $maxUs = $null
        foreach ($line in $summary) {
            if ($line -match 'MaxDPCTimeInUsec|Max DPC.*Usec') {
                $m = [regex]::Match($line, '(\d+(\.\d+)?)')
                if ($m.Success) { $maxUs = [double]$m.Value }
            }
        }
        return [ordered]@{ status = 'captured'; reason = 'xperf dpcisr (10s trace)'; maxDpcUs = $maxUs; raw = ($summary -join "`n") }
    } catch {
        return [ordered]@{ status = 'error'; reason = "$($_.Exception.Message)"; maxDpcUs = $null }
    } finally {
        if (Test-Path $etl) { Remove-Item $etl -Force -EA SilentlyContinue }
    }
}

function Get-AppxCounts {
    $cur = (Get-AppxPackage -EA SilentlyContinue).Count
    $all = $null
    if (Test-Admin) {
        try { $all = (Get-AppxPackage -AllUsers -EA Stop).Count } catch { $all = $null }
    }
    return [ordered]@{ currentUser = $cur; allUsers = $all }
}

function Get-ServiceCounts {
    $svc = Get-Service -EA SilentlyContinue
    $running = ($svc | Where-Object { $_.Status -eq 'Running' }).Count
    $auto = 0
    try { $auto = (Get-CimInstance Win32_Service -Filter "StartMode='Auto'" -EA SilentlyContinue).Count } catch { }
    return [ordered]@{ running = $running; autoStart = $auto; total = $svc.Count }
}

# ---------------------------------------------------------------------------
# COMPARE MODE
# ---------------------------------------------------------------------------
function Format-Delta($before, $after) {
    if ($null -eq $before -or $null -eq $after) { return 'n/a' }
    $d = $after - $before
    if ($d -is [double]) { $d = [math]::Round($d, 3) }
    $sign = ''
    if ($d -gt 0) { $sign = '+' }
    return "$sign$d"
}

if ($PSCmdlet.ParameterSetName -eq 'Compare') {
    if ($Compare.Count -ne 2) { throw 'Compare needs exactly two report .json paths: -Compare before.json after.json' }
    $b = Get-Content $Compare[0] -Raw | ConvertFrom-Json
    $a = Get-Content $Compare[1] -Raw | ConvertFrom-Json

    $rows = @()
    $rows += "| Metric | Before | After | Delta |"
    $rows += "|---|---|---|---|"
    $rows += "| Idle processes | $($b.metrics.processCount) | $($a.metrics.processCount) | $(Format-Delta $b.metrics.processCount $a.metrics.processCount) |"
    $rows += "| RAM in use (GB) | $($b.metrics.ramInUseGb) | $($a.metrics.ramInUseGb) | $(Format-Delta $b.metrics.ramInUseGb $a.metrics.ramInUseGb) |"
    $rows += "| Commit charge (GB) | $($b.metrics.commitChargeGb) | $($a.metrics.commitChargeGb) | $(Format-Delta $b.metrics.commitChargeGb $a.metrics.commitChargeGb) |"
    $rows += "| Appx (current user) | $($b.metrics.appx.currentUser) | $($a.metrics.appx.currentUser) | $(Format-Delta $b.metrics.appx.currentUser $a.metrics.appx.currentUser) |"
    $rows += "| Appx (all users) | $($b.metrics.appx.allUsers) | $($a.metrics.appx.allUsers) | $(Format-Delta $b.metrics.appx.allUsers $a.metrics.appx.allUsers) |"
    $rows += "| Services running | $($b.metrics.services.running) | $($a.metrics.services.running) | $(Format-Delta $b.metrics.services.running $a.metrics.services.running) |"
    $rows += "| Boot time (ms) | $($b.metrics.bootTime.ms) | $($a.metrics.bootTime.ms) | $(Format-Delta $b.metrics.bootTime.ms $a.metrics.bootTime.ms) |"
    $rows += "| Max DPC (us) | $($b.metrics.dpc.maxDpcUs) | $($a.metrics.dpc.maxDpcUs) | $(Format-Delta $b.metrics.dpc.maxDpcUs $a.metrics.dpc.maxDpcUs) |"

    $md = @()
    $md += "# Null OS Baseline - Before/After"
    $md += ""
    $md += "- Machine: $($a.system.manufacturer) $($a.system.model) (VM: $($a.system.isVirtualMachine))"
    $md += "- Build: $($a.system.edition) $($a.system.displayVersion) ($($a.system.buildNumber))"
    $md += "- Before: ``$([IO.Path]::GetFileName($Compare[0]))``  ->  After: ``$([IO.Path]::GetFileName($Compare[1]))``"
    $md += ""
    $md += $rows
    $md += ""
    $md += "> Lower is better for every row except boot-time source availability. DPC/appx-allUsers blank = not captured (see note in the source report)."

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outMd = Join-Path $OutDir "compare-$stamp.md"
    ($md -join "`r`n") | Set-Content -Path $outMd -Encoding UTF8
    Write-Host "[*] Comparison written: $outMd" -ForegroundColor Green
    $md -join "`n" | Write-Host
    return
}

# ---------------------------------------------------------------------------
# CAPTURE MODE
# ---------------------------------------------------------------------------
if ($SettleSeconds -gt 0) {
    Write-Host "[*] Settling $SettleSeconds s before measuring (let the shell go idle)..."
    Start-Sleep -Seconds $SettleSeconds
}

if (-not (Test-Admin)) {
    Write-Warning 'Not elevated - appx(all users), some services, and DPC capture will be skipped. Re-run as admin for a complete report.'
}

Write-Host '[*] Capturing baseline...' -ForegroundColor Cyan
$sys = Get-SystemContext
$boot = Get-BootTimeMs
$dpc  = Get-DpcLatency
$appx = Get-AppxCounts
$svc  = Get-ServiceCounts

$report = [ordered]@{
    schema   = 'nullos.baseline/1'
    profile  = $Profile
    label    = $Label
    system   = $sys
    metrics  = [ordered]@{
        processCount   = (Get-ProcessCount)
        ramInUseGb     = (Get-RamInUseGb)
        commitChargeGb = (Get-CommitChargeGb)
        bootTime       = $boot
        dpc            = $dpc
        appx           = $appx
        services       = $svc
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$base  = "{0}-{1}-{2}-{3}" -f $sys.buildNumber, $Profile, $Label, $stamp
$outJson = Join-Path $OutDir "$base.json"
$outMd   = Join-Path $OutDir "$base.md"

($report | ConvertTo-Json -Depth 6) | Set-Content -Path $outJson -Encoding UTF8

# markdown
$m = @()
$m += "# Null OS Baseline - $Profile / $Label"
$m += ""
$m += "Captured (UTC): $($sys.capturedUtc)"
$m += ""
$m += "## System"
$m += "| Field | Value |"
$m += "|---|---|"
$m += "| Edition | $($sys.edition) |"
$m += "| Version / Build | $($sys.displayVersion) / $($sys.buildNumber) |"
$m += "| Manufacturer / Model | $($sys.manufacturer) / $($sys.model) |"
$m += "| Virtual machine | $($sys.isVirtualMachine) |"
$m += "| CPU | $($sys.cpu) ($($sys.logicalCpus) logical) |"
$m += "| Total RAM (GB) | $($sys.totalRamGb) |"
$m += "| Elevated capture | $($sys.elevated) |"
$m += ""
$m += "## Metrics (idle)"
$m += "| Metric | Value |"
$m += "|---|---|"
$m += "| Idle processes | $($report.metrics.processCount) |"
$m += "| RAM in use (GB) | $($report.metrics.ramInUseGb) |"
$m += "| Commit charge (GB) | $($report.metrics.commitChargeGb) |"
$m += "| Boot time (ms) | $($boot.ms) |"
$m += "| Boot time source | $($boot.source) |"
$m += "| Max DPC (us) | $($dpc.maxDpcUs) |"
$m += "| DPC capture | $($dpc.status) - $($dpc.reason) |"
$m += "| Appx (current user) | $($appx.currentUser) |"
$m += "| Appx (all users) | $($appx.allUsers) |"
$m += "| Services running | $($svc.running) |"
$m += "| Services auto-start | $($svc.autoStart) |"
$m += "| Services total | $($svc.total) |"
$m += ""
$m += "> Capture on a clean VM before apply (``-Label before``) and again after (``-Label after``), then run ``-Compare before.json after.json``. Blank DPC/appx-allUsers means the capture was skipped (not elevated, or xperf absent) - the reason is recorded above. No number is ever fabricated."

($m -join "`r`n") | Set-Content -Path $outMd -Encoding UTF8

Write-Host ""
Write-Host "  Null OS baseline captured" -ForegroundColor Green
Write-Host "  -------------------------"
Write-Host "  profile   : $Profile / $Label"
Write-Host "  procs     : $($report.metrics.processCount)"
Write-Host "  RAM in use: $($report.metrics.ramInUseGb) GB"
Write-Host "  appx (cur): $($appx.currentUser)"
Write-Host "  svc runin : $($svc.running)"
Write-Host "  json      : $outJson"
Write-Host "  md        : $outMd"
