# Null OS

[![validate-build](https://github.com/null-os-official/Null/actions/workflows/ci.yml/badge.svg)](https://github.com/null-os-official/Null/actions/workflows/ci.yml)

Null OS isn't another debloat script. It's a highly opinionated, brutally
optimized configuration for **Windows 11 Pro**, applied cleanly through **AME
Wizard Beta** as a single `.apbx` playbook. It strips telemetry, culls
background workers, tames OEM/GPU bloat surgically, and tunes the latency path —
while staying **fully reversible**.

## What Null OS does
- **Zero telemetry** — DiagTrack, CEIP, Appraiser, error reporting, AppCompat
  inventory, and the telemetry scheduled tasks/autologgers are shut off.
- **Maximum privacy** — advertising ID, location, activity history, Cortana,
  Bing/web search, tailored experiences, Recall/Copilot AI data — locked down at
  machine, current-user, and new-user levels.
- **Brutal performance** — ~50 non-essential services culled, service-host
  grouping forced to collapse idle `svchost.exe` processes, background apps and
  capture disabled, visual effects trimmed (ClearType + tear-free DWM kept).
- **Minimal latency** — Win32PrioritySeparation, MMCSS gaming profile, network
  throttling off, per-NIC TCP tuning, kernel/boot timer path tuned, optional
  extreme low-latency power scheme.
- **Surgical, not scorched-earth** — Lenovo and NVIDIA telemetry/updaters are
  removed while thermal/fan control, Fn keys, and Optimus display switching are
  kept. Gaming dependencies and the WebView2 runtime survive.

## Reversible by design
Before touching anything, Null OS takes a **System Restore point** *and* **raw
registry + BCD backups** to `%SystemDrive%\NullOS-Backup`. Security-reducing
options (Defender, Windows Update, CPU mitigations, VBS) are **opt-in and off by
default**. Instead of killing Windows Update, the default is to **pin the build**
and defer updates — you keep security patches, you lose day-one breakage.

Neither Atlas OS nor Revi OS takes a raw reg/BCD backup. That's the point.

## Proof, not marketing
Every performance claim ships with a receipt. The [`bench/`](bench/) harness
captures idle process count, RAM in use, boot time, DPC latency, and appx/service
counts on a clean VM **before and after** apply, then diffs them:

```powershell
.\bench\Measure-Baseline.ps1 -Profile clean-vm -Label before
# apply playbook, reboot, settle
.\bench\Measure-Baseline.ps1 -Profile clean-vm -Label after -SettleSeconds 120
.\bench\Measure-Baseline.ps1 -Compare .\bench\reports\<before>.json,.\bench\reports\<after>.json
```

Idle RAM is shell-bound (explorer/dwm/SearchHost are unremovable), so the honest
metric is **delta vs clean Windows**, not a fixed absolute. Numbers without a
committed report in `bench/reports/` are not published. Verified baselines land
here as the clean-VM proof loop matures.

## Approach vs Atlas OS / Revi OS
Atlas maximizes aggression; Revi maximizes post-install control. Null OS aims to
be the only playbook that is **brutal AND reversible AND provable AND
hardware-aware** — enterprise-tier engineering where every tweak is documented,
gated behind a toggle, and undoable.

## Getting started
1. Grab the latest **AME Wizard Beta**.
2. Download the Null OS `.apbx` from [Releases](https://github.com/null-os-official/Null/releases).
3. Drag, drop, pick your toggles, apply. Reboot to finish.

> Building from source: `.\build.ps1` → `dist\NullOS-<version>.apbx`
> (requires a 7-Zip CLI on PATH or in `.\tools\`).

## Documentation
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — execution model, safety, and
  the full module breakdown (matches `Configuration/custom.yml` line-for-line).
- [`docs/PROFILES.md`](docs/PROFILES.md) — Competitive / Daily / Laptop
  recommended-toggle matrix.
- [`bench/README.md`](bench/README.md) — the baseline harness.
- [`control/README.md`](control/README.md) — Null Control Center (post-install
  dashboard + re-enable + restore).

## Contributing
Know Windows internals, networking stacks, or kernel tuning? Read the
architecture doc. Every change must be justified by a measurable win in the
`bench/` harness or an explicit privacy gain — and it must be reversible.
