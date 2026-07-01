# Null OS — Tweak IR (design)

> Status: **design, not implemented.** This is the target architecture and the
> order it must be built in. It is deliberately deferred — see "Why not yet".

## The problem it solves
The same tweak is currently encoded in **five** places, by hand:

1. `Configuration/custom.yml` — the action that applies it.
2. `playbook.conf` — the `<CheckboxOption>` that gates it.
3. `docs/ARCHITECTURE.md` / `docs/PROFILES.md` — the tables that describe it.
4. `control/NullControl.ps1` — detection + the `redebloat` family list.
5. `Configuration/custom.yml` §10d — the self-heal family list (again).

That's drift waiting to happen. The debloat family list already lives in three
places that must be kept in sync manually. Every new tweak multiplies the risk.

## The design
A single source of truth: a **Tweak IR** — one declarative record per tweak.

```yaml
# tweaks/debloat.bingnews.yml  (illustrative)
id: debloat.bingnews
category: debloat
gate: Debloat              # the playbook.conf <Name> that toggles it
title: "Remove Bing News"
rationale: "Ad-driven news app; pure bloat."
risk: low
profiles: [competitive, daily, laptop]
apply:
  - appx: { name: "Microsoft.BingNews*", type: family }
detect:                    # how NullControl knows it's applied
  - appx-absent: "Microsoft.BingNews*"
inverse: null              # reinstallable from Store; no scripted restore
```

A **compiler** (`tools/Compile-Tweaks.ps1`) reads all IR records and emits every
downstream artifact:

- `Configuration/custom.yml` (+ `Configuration/Tasks/*.yml` once modular)
- `playbook.conf` `<FeaturePages>` (respecting the 4-option page limit)
- `control/NullControl.ps1` detection map + `redebloat` list
- the doc tables in `ARCHITECTURE.md` / `PROFILES.md`

A **CI gate** regenerates the artifacts and fails the build if the committed
files drift from what the IR produces. After that, the IR is the *only* file a
contributor edits; everything else is generated and provably in sync. That is
what makes the "transparent and correct at scale" claim unbreakable.

## Why not yet (sequencing)
This is the P3 moat and it has hard prerequisites. Building it out of order is
how you mass-generate unverified changes.

1. **Engine must be modular first (F6).** The compiler should target clean
   per-category `Tasks/*.yml`, not a 248-line monolith. F6 itself is gated on the
   clean-VM proof loop, because splitting the working engine can only be trusted
   once an apply can be verified end-to-end (AME's `!task` expansion means a
   split cannot be proven equivalent by static parsing alone).
2. **Clean-VM proof loop must exist (P0/F1 harness → real baselines).** The
   compiler will regenerate the shipping engine; nothing regenerated ships
   without a before/after receipt from `bench/`.
3. **Then** build `tweaks/`, `Compile-Tweaks.ps1`, and the CI drift gate.

Until 1 and 2 are real, the honest move is to keep hand-editing the (verified)
monolith and accept the drift risk — not to bolt a code generator onto an engine
we can't yet validate. Shipping an unwired IR now would just create another
orphaned subsystem, which this project has been burned by before.

## Interim mitigation
Until the IR lands, treat `Configuration/custom.yml`'s debloat list as the
canonical family set, and keep `control/NullControl.ps1` (`redebloat`) and §10d
(self-heal) in sync with it by hand whenever it changes. A single grep of the
three lists during review catches drift.
