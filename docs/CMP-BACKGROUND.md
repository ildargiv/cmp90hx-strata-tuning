# CMP background (internet research, added Chapter 2)

Community and vendor findings collected to decide what the hardware mods should be. Everything
here is unconfirmed static/second-hand until measured on our own cards; our measurements live in
the README, not here.

## Why a CMP card is "locked to Gen1 x4"

NVIDIA shipped the CMP (Cryptocurrency Mining Processor) cards with the power-delivery capacitors
around the core **deliberately unsoldered** and some PCIe lanes disabled at the board level, so the
cards could not easily be resold as gaming GPUs. The accepted community fix is to **solder the
missing capacitors**; on the CMP 90HX this lifts the PCIe link from **Gen1 x4 to Gen2 x16** (the
reported device max). Sources: Tom's Hardware / LTT coverage of the CMP family (with soldering
analysis), and the capacitor-mod documentation used on the CMP 170HX
(`github.com/amoghmunikote/170th-street`, `modifications/pcie-capacitor-mod.md`), which shows the
exact LnkSta change `2.5GT/s, x4 → 2.5GT/s, x16`.

## CMP 90HX (GA102)

- GA102-100 (`220D-100-A1`), 80 SM, 6400 shading units — the same silicon family as the RTX 3080.
- Board **PG132** (RTX 3080 layout).
- 10 GB GDDR6X, 320-bit, ~760 GB/s. Matches our read-back of 9501 MHz memory.
- Mining TDP ~320 W (2x 8-pin); our card's vBIOS caps at **250 W**.
- Community report on this exact model running Qwen3.8-Flash-Next in Strata ("mining farm" thread):
  the **Gen2 unlock alone was +12% decode**, and it confirmed PCIe bandwidth was the bottleneck,
  not the GPUs. We see the same shape of numbers without the caps (see README Chapter 1).

## CMP 50HX (TU102)

- TU102-100, **Turing** (sm_75) — do NOT confuse with the 90HX's Ampere GA102.
- **3584 CUDA cores** — a cut-down TU102 (RTX 2080 Ti has 4352); ~11 TFLOPS FP32.
- Board **PG150** (RTX 2080 Ti layout).
- 10 GB GDDR6, 320-bit, ~560 GB/s (slower than the 90HX's GDDR6X).
- ~210-220 W. Same Gen1 x4 stock link and missing-capacitor story.
- Plan for our card: **upgrade the memory to 20 GB**, which changes its role to the fleet's
  high-VRAM card for AI. Turing sm_75 also means Strata's sm_80+ opt-in kernels do not all apply.

## Consequences for this repo

- The **90HX is the lead Strata card** here (Ampere, more cores, GDDR6X, sm_86 kernels).
- The **50HX/20 GB** is the high-VRAM card, tested in applications where VRAM matters more than
  PCIe streaming.
- Every benchmark must record the current hardware state (caps soldered or not, link gen/width,
  memory size) so the history is honest as these mods happen.

Links (visited 1 Nov 2026): TechPowerUp CMP 90HX / CMP 50HX spec pages; WCCFTech CMP family
details; MSI CMP 50HX MINER press; Tom's Hardware CMP 170HX unlock article; LTT Labs cmpunlocker
article; r/LocalLLM "Qwen3.8-Flash-Next on a CMP 90HX mining farm"; amoghmunikote capacitor-mod doc.
