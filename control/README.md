# Null Control Center

Post-install control for a Null OS machine — the answer to Revi OS's Revision
Tool, and then some. Because the Null OS playbook takes a **raw registry + BCD
backup** before it applies anything, this tool can **restore from that backup** —
something Revi's tool cannot do.

## Run

```powershell
# Read-only dashboard (no admin needed):
.\NullControl.ps1

# Re-enable something (run in an elevated shell):
.\NullControl.ps1 -Action enable-defender
.\NullControl.ps1 -Action enable-update
.\NullControl.ps1 -Action enable-vbs

# Fix a flaky over-install debloat, live:
.\NullControl.ps1 -Action redebloat

# Roll the machine back to its pre-Null-OS registry/BCD:
.\NullControl.ps1 -Action restore-backup
```

## What the dashboard shows
- **Live**: process count, RAM in use, running services, appx count.
- **Null OS state**: which hardening is currently applied — telemetry, Defender,
  Windows Update, build pinning, svchost grouping, VBS, CPU mitigations,
  OneDrive removal. Detected live from the registry / service state, not
  assumed.

## Actions
| Action | Effect | Elevated |
|---|---|---|
| `status` (default) | Dashboard | no |
| `enable-defender` | Clears Defender disable policy + realtime pref | yes |
| `enable-update` | wuauserv/UsoSvc/WaaSMedicSvc → Manual, clears NoAutoUpdate | yes |
| `enable-vbs` | Re-enables VBS / memory integrity | yes |
| `redebloat` | Live, elevated re-purge of the known-bloat appx list | yes |
| `restore-backup` | `reg import` services/policies + `bcdedit /import` from `NullOS-Backup` | yes |

`restore-backup` prompts for a typed `RESTORE` confirmation (skip with `-Force`).
A System Restore point named **Null OS Pre-Apply** also exists (`rstrui.exe`) as
a second safety net.

## Notes
- Windows PowerShell 5.1-safe.
- State changes generally need a **reboot** to fully take effect.
- The known-bloat list in `redebloat` mirrors `Configuration\custom.yml`; keep
  them in sync when the playbook's debloat list changes.
