# Null OS — Install & ISO Integration

There are two ways to apply Null OS. The second is how you get the honest,
publishable performance numbers.

## A. On an existing install (quick, less clean)
1. Get **AME Wizard Beta**.
2. Download `NullOS-<version>.apbx` from
   [Releases](https://github.com/null-os-official/Null/releases) (or build it,
   below).
3. Open it in AME Wizard, pick your toggles (see
   [PROFILES.md](PROFILES.md)), apply, reboot.

Over-existing-install applies can be flaky — Windows sometimes leaves appx
packages behind. Null OS registers a **first-boot self-heal** (RunOnce) that
re-purges the bloat list and writes `C:\ProgramData\NullOS\selfheal-receipt.txt`
on first logon. Run [`control/NullControl.ps1`](../control/NullControl.ps1)
afterward to confirm state.

## B. Clean-install integration via Audit Mode (recommended)
This applies Null OS to a pristine image before any user account exists — the
cleanest result, and the only way to capture a trustworthy baseline.

1. Boot the **Windows 11 Pro** installer. At the first OOBE screen (region
   select), press **Ctrl+Shift+F3**. Windows reboots into **Audit Mode** as the
   built-in Administrator, with a Sysprep dialog on the desktop.
2. *(Proof loop — optional but recommended)* Capture the clean baseline:
   ```powershell
   .\bench\Measure-Baseline.ps1 -Profile clean-vm -Label before
   ```
3. Run AME Wizard + the Null OS `.apbx`. Pick toggles, apply.
4. Reboot back into Audit Mode (leave the Sysprep dialog open / re-enter if
   needed), let it settle, then:
   ```powershell
   .\bench\Measure-Baseline.ps1 -Profile clean-vm -Label after -SettleSeconds 120
   .\bench\Measure-Baseline.ps1 -Compare .\bench\reports\<before>.json,.\bench\reports\<after>.json
   ```
   Commit the resulting report — that is the receipt for every claim.
5. Reseal for deployment:
   ```powershell
   %WINDIR%\System32\Sysprep\sysprep.exe /oobe /generalize /shutdown
   ```
   The next boot runs OOBE as if it were a fresh machine, with Null OS baked in.
6. *(Optional)* Capture the image with DISM for reuse:
   ```powershell
   Dism /Capture-Image /ImageFile:C:\nullos.wim /CaptureDir:C:\ /Name:"Null OS"
   ```

> Do this in a **VM** for the published baseline (clean, reproducible, no OEM
> variables). Real-hardware numbers are reported as a delta per profile in
> [`bench/`](../bench/), never as a single absolute.

## Building the `.apbx` yourself
```powershell
.\build.ps1                 # -> dist\NullOS-<version>.apbx  (prints SHA-256)
.\build.ps1 -OutDir release # custom output dir
```
Requires a 7-Zip CLI on `PATH` or dropped in `.\tools\`. The archive password is
`malte` (the fixed password AME Wizard Beta expects for beta playbooks).

## Release integrity & signing
`build.ps1` prints the artifact **SHA-256** — publish it on the GitHub Release so
users can verify the download. CI (`validate-build`) also builds the `.apbx` and
uploads it as an artifact on every push.

**Authenticode / GPG signing is not automated here** because it requires a
signing certificate / key that only the maintainer holds — never commit one.
When you have one, sign the release artifact locally:

```powershell
# Authenticode (code-signing cert):
Set-AuthenticodeSignature -FilePath dist\NullOS-<ver>.apbx `
  -Certificate (Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert)[0] `
  -TimestampServer http://timestamp.digicert.com

# or GPG detached signature:
gpg --armor --detach-sign dist\NullOS-<ver>.apbx   # -> .apbx.asc
```

Attach the signature (or at minimum the published SHA-256) to the Release. To
automate later, store the key as a GitHub Actions secret and add a signing step
to `ci.yml` gated on `github.event_name == 'release'`.
