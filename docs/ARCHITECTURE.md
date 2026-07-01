# Null OS Architecture

Modern Windows is weighed down by telemetry, background workers, and services
that benefit the vendor, not the user. Null OS reverses that: a highly
opinionated, brutally optimized configuration for Windows 11 Pro, applied via
**AME Wizard Beta**. Everything here describes what the shipping playbook
actually does — no aspirational claims. If it's documented, it's in
`Configuration/custom.yml`.

## Execution Model (how it really runs)

Null OS ships as a `.apbx` (a password-protected 7-Zip archive AME Wizard
extracts). Two files matter:

- **`playbook.conf`** — XML manifest. Metadata (Name, Version, SupportedBuilds,
  Requirements) **and the feature-toggle GUI only** (`CheckboxPage` /
  `RadioPage`). No actions live here. Each option exposes a `<Name>`.
- **`Configuration/custom.yml`** — the execution engine, and the *only* file AME
  runs. Every action is gated on a feature `<Name>` from `playbook.conf` via
  `option: 'Name'` (or inverse `option: '!Name'`). Uncheck a box → its actions
  are skipped.

> `playbook.yaml` in the repo root is a dead signpost — AME ignores it. It only
> exists to document that `custom.yml` is the real engine.

### Why the engine is self-contained
Under this AME build, the TrustedInstaller node's working directory for launched
processes is invalid: `exeDir: true` on `!cmd` / `!powerShell` fails with "the
directory name is invalid". That means **bundled `.reg` imports and bundled
`.ps1` launches both fail.** So `custom.yml` uses only forms proven to work:

- Native directives that run internally as TrustedInstaller (no process launch):
  `!registryValue`, `!service`, `!appx`, `!scheduledTask`.
- Inline `!powerShell` with a `command: |` block and **no `exeDir`**.
- `!run` for direct executables (e.g. `bcdedit`, `netsh`) with no `exeDir`.

Inline PowerShell must be **Windows PowerShell 5.1-safe** (no ternary, no `??`,
no `if`-as-expression). `0xffffffff` DWORDs are written via `reg add`, not
`New-ItemProperty` (5.1 turns the literal into `-1`).

### Build
`build.ps1` packs `playbook.conf` + `Configuration/` into
`dist\NullOS-<version>.apbx` (7-Zip, AES-256, encrypted headers, password
`malte` — the fixed password AME Beta expects). It refuses to build if the
required payload is missing and prints the SHA-256 of the artifact.

## Safety Model (before anything changes)

Null OS is brutal but reversible. Before the first modification, `custom.yml`:

1. Enables System Restore and takes a **`Null OS Pre-Apply` restore point**.
2. Exports **raw registry backups** (`HKLM\SYSTEM\...\Services`,
   `HKLM\SOFTWARE\Policies\...\Windows`) and **`bcdedit /export`** to
   `%SystemDrive%\NullOS-Backup`.

Neither Atlas OS nor Revi OS takes a raw registry + BCD backup. This is the
foundation of the reversibility guarantee.

Per-user privacy changes are also written into the **default user hive**
(`C:\Users\Default\NTUSER.DAT` loaded as `HKU\AME_UserHive_Default`), so newly
created accounts inherit the lockdown, not just the current user.

## Modules (gated, in apply order)

| # | Module | Toggle | What it does |
|---|---|---|---|
| 0 | Rollback net | always | Restore point + raw reg/BCD backup; load default hive |
| 1 | Telemetry | `Telemetry` | DiagTrack off, DataCollection/CEIP/Appraiser/WER policies, autologgers off, telemetry scheduled tasks disabled, **NVIDIA telemetry/updater workers tamed (display container kept)** |
| 2 | Privacy | `Privacy` | Advertising ID, location, activity history, Cortana, web/Bing search, tailored experiences, Recall/Copilot AI data, dynamic lighting — machine + current user + default hive |
| 3 | Network | `Networking` | LLMNR off, SMB bandwidth-throttle off, anonymous-access lockdown, Remote Assistance off (policy + firewall rule) |
| 4 | Service cull | `ServiceCull` | ~50 non-essential services set to disabled (startup=4). **WSearch is never touched** (disabling it breaks Start/taskbar search) |
| 4b | svchost grouping | `ForceSvcGrouping` | Raises `SvcHostSplitThresholdInKB` above installed RAM so per-service `svchost.exe` processes collapse into shared hosts — the single biggest idle-process-count drop. Takes effect on reboot |
| 5 | Visual FX | `VisualFX` | Animations + transparency off; **ClearType font smoothing and tear-free DWM kept** |
| 6 | Debloat | `Debloat` | Curated appx removal (Bing apps, Solitaire, Clipchamp, consumer Teams, Copilot, OneNote/People/Skype, Zune, Journal, etc.); Edge background/updater neutralized (+ optional full Edge removal via `RemoveEdge`, WebView2 preserved); Widgets/Feeds off; GameDVR background capture off (Game Pass apps kept) |
| 7 | Hardware toggles | `!KeepBluetooth` / `!KeepPrintSpooler` / `!KeepXbox` | Inverse-gated: only removes Bluetooth / Print Spooler / Xbox UWP if you uncheck "keep" |
| 7b | OEM trim (Lenovo) | `OEMDebloat` | Strips Lenovo telemetry/updater/marketing apps + tasks + services, with an explicit **keep-list protecting `ImControllerService` + Vantage thermal/power backend** so Fn+Q performance modes, fan control, and battery conservation still work |
| 8 | Performance/latency | always + `LatencyExtreme` | Win32PrioritySeparation, network-throttling off, MMCSS Games profile, TcpAckFrequency/TCPNoDelay per NIC, `SvcHostSplitDisable`, last-access + FTH off, hiberboot off, power throttling off, high-performance plan; **Extreme** adds a custom `Null OS` power scheme + `DisablePagingExecutive` (desktop/plugged-in only) |
| 9 | Kernel/boot | `KernelTweaks` | `disabledynamictick`, `tscsyncpolicy Enhanced`, remove `useplatformclock`, `DistributeTimers` — no forced HPET |
| 9b | Danger (opt-in) | `DisableMitigations` / `DisableVBS` / `DisableMemoryCompression` | Spectre/Meltdown mitigations, VBS/HVCI/Credential Guard, RAM compression off. Anti-cheat CFG is re-enabled per-process even when system CFG is disabled |
| 10 | Disk footprint | `GutWinSxS` / `GutWinSxSResetBase` | DISM component cleanup + remove `Windows.old`; ResetBase drops uninstall-updates ability. **Off by default** (slow — pulls WU/servicing) |
| 10c | Update pinning | `PinWindowsBuild` | Defers feature updates 365d, quality 4d, pins `TargetReleaseVersion`. **Security patches still arrive** — the safe middle ground vs disabling WU entirely |
| 11 | Danger (opt-in) | `DisableDefender` / `DisableWindowsUpdate` | Off by default; require you to provide your own equivalent |
| 12 | Finalize | always | Unload default hive; write completion status |

## What we deliberately keep

Aggression only where it's free. Never at the cost of a broken system:

- **WSearch** — disabling it breaks Start/taskbar search.
- **ctfmon** — breaks text input.
- **DWM** — mandatory compositor.
- **NvContainerLocalSystem** — drives Optimus / hybrid-graphics display
  switching; killing it can black-screen a laptop.
- **ImControllerService + Vantage thermal/power backend** — Fn keys, fan
  control, performance modes.
- **Gaming dependencies** (GamingServices, Xbox auth when Xbox kept) and the
  **WebView2 runtime** (even when Edge is fully removed).

## Proof, not marketing

Every performance claim ships with a reproducible receipt. `bench/` contains the
**baseline harness** (`Measure-Baseline.ps1`): capture idle process count, RAM in
use, boot time, DPC latency, and appx/service counts on a clean VM before apply
and again after, then diff them. See [`bench/README.md`](../bench/README.md).

Idle RAM is shell-bound (explorer / dwm / SearchHost are unremovable), so the
honest metric on real hardware is **delta vs clean Windows**, captured by the
harness — not a fixed absolute. Numbers without a matching report in
`bench/reports/` are not published.

## Differentiators vs Atlas OS / Revi OS

- **Reversible by design** — raw reg/BCD backup + restore point they don't take.
- **Hardware-aware** — surgical Lenovo/NVIDIA trimming instead of vendor-agnostic
  blanket removal.
- **Update pinning** instead of killing Windows Update — you keep security
  patches and lose only day-one breakage.
- **Provable** — the `bench/` harness makes every claim checkable.

Null OS is not for everyone. It's for those who demand total, *undoable* control
over their hardware.
