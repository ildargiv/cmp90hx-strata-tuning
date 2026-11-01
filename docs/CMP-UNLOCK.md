# CMP 90HX: what "special drivers" actually means

Internet research behind Chapter 3, kept here so the numbers there are reproducible and the
claims are attributable. Every statement below is either quoted from the linked project or
measured on our own card (`results/raw/`).

## Short answer

**There is no official NVIDIA "mining driver" for CMP cards.** The 90HX runs on the ordinary
GeForce/Studio driver branch (616.92 on this machine) and no NVIDIA package removes its limits.

What does exist is a community unlock, and it is not a driver in the usual sense: it is an
exploit of the GPU's own secure coprocessor. It is real, it is open source, and on our card it
was worth **29×** on a compute-bound workload (Chapter 3).

## Why the card is slow

The 90HX is a physically complete GA102 (`10de:220d`, 6400 CUDA cores, **50 SM**, 320-bit
GDDR6X, 760 GB/s). Nothing is fused off. Instead, eFuse bits set **SM issue-rate modifiers**:
the SMs work, but they are allowed to issue instructions at a fraction of the normal rate.

This is why the locked card looks healthy on every sensor while being slow:

| Sensor | Locked value (our card) | Comment |
|---|---|---|
| SM clock | 1860 MHz of 2100 | not clock-limited |
| Temperature | 49–51 °C of 93 °C | not thermal-limited |
| Power | 110.7 W of 250 W | **not** power-limited |
| Utilisation | 100 % | the driver says "busy" — the ALUs are mostly starved |

VBIOS mods cannot fix this: eFuse values override the BIOS tables. The throttle is bypassed by
writing the `FEAT_OVR` override registers (`SS0=0x88888888`, `SS1=0x00000008`), which only
become writable after the **PLM** (Privilege Level Masks) are opened — which requires arbitrary
code execution on the **GSP Falcon** coprocessor. The entry point is a stack-canary bug in the
shipping SEC2 debug booter, disclosed by Jon Pry, *"A Canary in the Crypto Mine: Defeating Stack
Protection in a GPU Secure Coprocessor"* (DOI [10.5281/zenodo.20916112](https://zenodo.org/records/20916112)).
The payload is known as **V67**.

## The four things people call "unlocking" (they are unrelated)

| # | What | How | What it gives | Status |
|---|---|---|---|---|
| 1 | **Compute unlock** | GSP exploit V67; patched driver (Linux) or EFI bootloader (Windows) | Full SM issue rate: llama.cpp prefill **224 → 1770 t/s (×7.9)** per the project; **×29 on PearlHash** on our card | works, open source |
| 2 | **PCIe width ×16** | **soldering** 220 nF AC-coupling capacitors on the missing lanes | Gen1 ×4 (~1 GB/s) → Gen1 ×16 (~4 GB/s) | works, hardware |
| 3 | **PCIe Gen2** | `iatethelogs/cmp90hx_pwner`: XVE register `0x088fe8` + FLR + retrain | Gen2 ×16, measured **6.33 / 6.40 GB/s** DMA | works, Linux |
| 4 | **Patched driver for rendering** | `dartraiden/NVIDIA-patcher` | image output / games | graphics only, irrelevant to mining or AI |

Only #4 resembles a "special driver", and it is needed solely to drive a display. The stock
driver works fine for compute once #1 is applied.

## Projects

- [`WildFlash1st/cmp90hx-unlock`](https://github.com/WildFlash1st/cmp90hx-unlock) — Linux stack
  (`cmpunlocker`), rejoin15 profile on NVIDIA Open 610.43.03, persistent across reboots.
- [`WildFlash1st/cmp90hx-unlock-for-windows`](https://github.com/WildFlash1st/cmp90hx-unlock-for-windows)
  — **the path used here**: EFI application on a USB stick, runs before the OS, open source,
  v3.05 as of 2026-09-30.
- [`iatethelogs/cmp90hx_pwner`](https://github.com/iatethelogs/cmp90hx_pwner) — compute unlock +
  PCIe Gen2 + P2P in one menu (Linux).
- [`bendy2/cmp90hx`](https://github.com/bendy2/cmp90hx) — the V67 direct-compute patch.
- [`jdowning100/cmpunlocker`](https://github.com/jdowning100/cmpunlocker) — rejoin16 PLM/render-mask
  method and the original Gen2 claim (Gen2 ×4, ~1.7 GB/s).
- [`dartraiden/NVIDIA-patcher`](https://github.com/dartraiden/NVIDIA-patcher) — patched driver for
  rendering.

## What does not work (checked, not assumed)

- **Cross-flashing an RTX 3080 VBIOS** onto the 90HX. The project tried it with `nvflashk`
  (ID-check bypass): the flash is accepted, Device ID becomes `10DE:2206`, GSP firmware loads —
  then **hangs at progress `0x1`, GDDR6X memory training**, because the boards differ
  (JPG132 vs PG132). Source: `docs/VBIOS_EXPERIMENT.md` in the unlock repo. Conclusion: there
  are no "modified vBIOS with a raised power limit" for this card, and there cannot be one.
- **Raising the power limit by software.** `nvidia-smi` reports `Min 100 W / Max 250 W`, both
  read-only on this card.
- **Memory overclocking headroom.** Memory runs at 9501 MHz, i.e. 19 Gb/s — already the
  GDDR6X rating. There is nothing left to gain there.

## Windows path: constraints that matter

- **The unlock is volatile.** Any full reboot (POST re-runs the VBIOS) re-locks the card. Boot
  from the USB stick again — the unlock survives an FLR but not a POST.
- **Secure Boot must be off** (the loader is unsigned).
- One card per boot iteration in multi-card systems (we have one card, so irrelevant).
- The unlock runs before the OS, so it is driver-version independent: the stock 616.92 is fine
  for compute. Rendering needs project #4.
- Rollback is free: reboot and the card is stock again.

## Reference points for judging results

| Card | SM | PearlHash (compute-bound) | Ethash (memory-bound) |
|---|---|---|---|
| CMP 90HX, locked | 50 | **2.94 TH/s** (ours) | 86–98 MH/s |
| CMP 90HX, unlocked | 50 | **85.85 TH/s** (ours) | not measured |
| RTX 3080 | 68 | ~100 TH/s | ~95–100 MH/s |

The locked card reaches ~90 % of an RTX 3080 on **Ethash** and ~3 % on **PearlHash**. Same
silicon, same memory: the difference is only whether the algorithm depends on SM issue rate.
That asymmetry is the cleanest evidence that the throttle is a compute-issue throttle and not a
damaged die.
