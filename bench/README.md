# Null OS — Baseline Harness

Proof, not marketing. This is how every Null OS performance claim earns a
receipt. No number ships without a matching report in `reports/`.

## Why
Null OS targets measurable wins over stock Windows (and over Atlas OS / Revi OS).
"Faster" and "lighter" mean nothing without a reproducible before/after on the
same hardware. `Measure-Baseline.ps1` captures that snapshot and diffs two of
them.

## What it captures
- Idle process count
- Physical RAM in use (the headline "idle RAM") + commit charge
- Boot time (`MainPathBootTime` from the Diagnostics-Performance log; falls back
  to uptime if that log is disabled)
- DPC/ISR latency — best-effort via `xperf` (Windows Performance Toolkit / ADK).
  If `xperf` is absent or the run isn't elevated, it records `skipped` with the
  reason. **It never fabricates a latency number.**
- Installed appx count (current user, + all users when elevated)
- Service counts (running / auto-start / total)
- Full system context (edition, build, model, CPU, RAM, VM detection, elevation)

## Usage
Run **as administrator** for a complete report (appx-all-users, services, and
DPC need elevation).

```powershell
# 1. On a CLEAN Win11 VM, before applying the Null OS playbook:
.\Measure-Baseline.ps1 -Profile clean-vm -Label before

# 2. Apply the playbook, reboot, let the desktop settle, then:
.\Measure-Baseline.ps1 -Profile clean-vm -Label after -SettleSeconds 120

# 3. Diff them (comma-separated - it's one array parameter):
.\Measure-Baseline.ps1 -Compare .\reports\<before>.json,.\reports\<after>.json
```

Output lands in `reports/` as both `.json` (machine-readable, for CI) and `.md`
(human-readable, for the README / release notes).

## Profiles
Use a consistent `-Profile` per hardware class so reports are comparable:
`clean-vm`, `ultrabook`, `gaming-laptop`. Honest per-profile budgets live in the
(local) mega-plan; the harness output is what proves or disproves them.

## Notes
- Windows PowerShell 5.1-safe.
- Run it at true idle: nothing open, a couple minutes after login. Idle RAM is
  shell-bound (explorer/dwm/SearchHost), so sub-2GB "with apps open" is
  physically impossible — compare like-for-like idle only.
- `reports/*.json` are the source of truth; the `.md` files are rendered from
  them. Commit the reports you want to publish as receipts.
