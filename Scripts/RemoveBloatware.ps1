#Requires -RunAsAdministrator
<#
    Null OS - UWP bloatware removal.

    Strategy: explicit remove-list, NOT remove-all-except. A curated list is
    auditable and cannot accidentally strip a component the OS depends on.
    A hard KEEP guard is applied on top as a second safety net: anything that
    matches $Keep is never touched even if it also matches a remove pattern.

    Removes both the installed package (all users) and the provisioned package
    (so new user profiles start clean). Idempotent and non-fatal per item.

    Invoked by Configuration\main.yml (gated on the 'Debloat' feature).
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# --- Hard keep guard: NEVER remove these, period. -------------------------
# Store + installer, runtime frameworks, WebView2, terminal/console, core
# shell utilities, security UI, and all OEM/GPU/audio vendor packages.
$Keep = @(
    '*WindowsStore*'
    '*StorePurchaseApp*'
    '*DesktopAppInstaller*'        # winget
    '*WindowsTerminal*'
    '*VCLibs*'
    '*NET.Native*'
    '*UI.Xaml*'
    '*WebView2*'
    '*WebpImageExtension*'
    '*HEIFImageExtension*'
    '*VP9VideoExtensions*'
    '*HEVCVideoExtension*'
    '*RawImageExtension*'
    '*AV1VideoExtension*'
    '*SecHealthUI*'                # Windows Security UI
    '*WindowsNotepad*'
    '*Paint*'
    '*WindowsCalculator*'
    '*ScreenSketch*'              # Snipping Tool
    '*Photos*'
    '*GamingServices*'           # PC Game Pass dependency
    '*Xbox.TCUI*'                # base xbox identity (Xbox app removal is gated in main.yml)
    '*XboxIdentityProvider*'
    '*NVIDIA*'
    '*AMD*'
    '*Realtek*'
    '*Intel*'
    '*Waves*'
    '*Synaptics*'
    '*Lenovo*'
    '*Dell*'
    '*HP*'
    '*ASUS*'
)

# --- Curated removal targets ----------------------------------------------
$Remove = @(
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.BingFinance'
    'Microsoft.BingSports'
    'Microsoft.BingSearch'
    'Microsoft.Microsoft3DViewer'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.Office.OneNote'
    'Microsoft.MicrosoftStickyNotes'
    'Microsoft.People'
    'Microsoft.windowscommunicationsapps'   # Mail & Calendar
    'Microsoft.SkypeApp'
    'Microsoft.Getstarted'                   # Tips
    'Microsoft.GetHelp'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.MixedReality.Portal'
    'Microsoft.Wallet'
    'Microsoft.WindowsMaps'
    'Microsoft.WindowsSoundRecorder'
    'Microsoft.Todos'
    'Microsoft.PowerAutomateDesktop'
    'Microsoft.Whiteboard'
    'Microsoft.MicrosoftJournal'
    'Microsoft.OutlookForWindows'            # new Outlook stub
    'MicrosoftTeams'                         # consumer Teams / chat
    'MSTeams'
    'Microsoft.Clipchamp'
    'Clipchamp.Clipchamp'
    'Microsoft.549981C3F5F10'                # Cortana
    'Microsoft.Copilot'
    'Microsoft.Windows.Ai.Copilot.Provider'
    'Microsoft.WindowsFamily'
    'Microsoft.Family'
    'Microsoft.QuickAssist'
    'MicrosoftCorporationII.QuickAssist'
    'MicrosoftWindows.CrossDevice'
    'Microsoft.ZuneMusic'                    # Media Player (legacy Groove) - Photos/Films
    'Microsoft.ZuneVideo'
    'Microsoft.GamingApp'                    # Xbox app (also gated natively in main.yml)
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.Xbox.TCUI'
)

function Test-Keep {
    param([string]$Name)
    foreach ($k in $Keep) { if ($Name -like $k) { return $true } }
    return $false
}

$removedCount = 0

foreach ($target in $Remove) {

    if (Test-Keep $target) {
        Write-Output "SKIP (keep-guard): $target"
        continue
    }

    # Installed packages, all users
    $pkgs = Get-AppxPackage -AllUsers -Name "*$target*" -ErrorAction SilentlyContinue
    foreach ($p in $pkgs) {
        if (Test-Keep $p.Name) { continue }
        try {
            Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
            Write-Output "removed pkg : $($p.Name)"
            $removedCount++
        } catch {
            Write-Output "FAILED pkg  : $($p.Name) -> $($_.Exception.Message)"
        }
    }

    # Provisioned package (affects future user profiles)
    $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "*$target*" }
    foreach ($pp in $prov) {
        if (Test-Keep $pp.DisplayName) { continue }
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
            Write-Output "removed prov: $($pp.DisplayName)"
        } catch {
            Write-Output "FAILED prov : $($pp.DisplayName) -> $($_.Exception.Message)"
        }
    }
}

Write-Output "Null OS debloat complete. Packages removed this pass: $removedCount"
exit 0
