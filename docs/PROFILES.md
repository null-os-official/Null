# Null OS — Profiles

AME Wizard applies exactly the toggles you check on the feature pages. It can't
pre-select them from a "profile" dropdown, so profiles here are **recommended
toggle sets** — check the boxes in the column that matches your machine. Every
option stays individually overridable.

Legend: **✓** check it · **–** leave unchecked · **opt** your call.

| Toggle (`Name`) | Competitive | Daily | Laptop |
|---|:---:|:---:|:---:|
| Telemetry | ✓ | ✓ | ✓ |
| Privacy | ✓ | ✓ | ✓ |
| Debloat | ✓ | ✓ | ✓ |
| ServiceCull | ✓ | ✓ | ✓ |
| VisualFX | ✓ | opt | ✓ |
| Networking | ✓ | ✓ | ✓ |
| ForceSvcGrouping | ✓ | ✓ | ✓ |
| RemoveEdge | ✓ | opt | opt |
| KernelTweaks | ✓ | ✓ | ✓ |
| OEMDebloat | ✓ | ✓ | ✓ |
| PinWindowsBuild | ✓ | ✓ | ✓ |
| RemoveOneDrive | ✓ | opt | opt |
| BlockTelemetryHosts | ✓ | opt | opt |
| KeepBluetooth | opt | ✓ | ✓ |
| KeepPrintSpooler | opt | ✓ | opt |
| KeepXbox | – | ✓ | opt |
| GutWinSxS | opt | – | – |
| GutWinSxSResetBase | opt | – | – |
| DisableMitigations | ✓ ⚠ | – | – |
| DisableVBS | ✓ ⚠ | – | – |
| DisableMemoryCompression | opt | – | – |
| DisableDefender | ⚠ only w/ own AV | – | – |
| DisableWindowsUpdate | – | – | – |
| **Latency profile** | **Extreme** | Balanced | **Balanced** |

## The three profiles

### Competitive — desktop / plugged-in, max aggression
For a machine that's basically a gaming rig. Squeezes latency and idle overhead
hard. Assumes you accept reduced security surface and supply your own AV if you
disable Defender. **Latency: Extreme** (pins CPU performance, disables power
saving — never do this on battery). ⚠ items reduce security; enable only if you
understand the trade.

### Daily — balanced daily-driver (the safe default)
The Revi-style "fast but stable" setup. Keeps Bluetooth, printing, Xbox, Defender,
VBS, and mitigations. Removes telemetry/bloat and tunes latency without touching
anything a normal user relies on. **Latency: Balanced.** If unsure, use this.

### Laptop — ultrabook / battery-aware
Same privacy/debloat wins, but **never** the Extreme power scheme (it kills
battery and disables power saving). OEMDebloat is safe here — the keep-lists
protect thermal/fan/hotkey backends. Skip `GutWinSxS` (slow, pulls servicing).
**Latency: Balanced.**

## Rules that override any profile
- **Extreme latency is desktop/plugged-in only.** On a laptop it wrecks battery.
- **Don't disable Defender** unless a third-party AV is installed and running.
- **DisableWindowsUpdate stays off** in every profile — `PinWindowsBuild` is the
  intended way to avoid bad updates while keeping security patches.
- On laptops with hybrid graphics, leave GPU/OEM keep-lists intact (default).

After applying, run [`control/NullControl.ps1`](../control/NullControl.ps1) to
confirm which changes are live and to re-enable anything you want back.
