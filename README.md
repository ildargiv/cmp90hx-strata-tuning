# Strata on an NVIDIA CMP 90HX (GA102, 10 GB): the card's history

Our own measurements of [Strata](https://github.com/Niko1221/Strata) (engine 0.1.54, app 0.2.8)
running Qwen3.8-Flash-Next **IQ3_XXS** on a single **NVIDIA CMP 90HX** in a Ryzen 7 5700G desktop,
Windows 10. Every number in this repository was produced on that machine. Raw data is in
`results/raw/`, the scripts and configs that made it are in `scripts/`.

This repository is the running history of the card, updated chapter by chapter as we tune it and
test it in different applications. Chapter 1 (this file) is the hardware profile and the first
baseline. The previous card (RTX 3060 12 GB) has its own history:
[rtx3060-strata-tuning](https://github.com/ildargiv/rtx3060-strata-tuning).

---

## Chapter 1 (1 Nov 2026): hardware profile and Strata baseline

### Hardware profile

| Field | Value |
|---|---|
| Product | NVIDIA CMP 90HX |
| Architecture | Ampere, GA102 (`220D-100-A1`), 80 SM |
| Memory | 10 GB GDDR6, 10 240 MiB total |
| Drivers | 616.92 (CUDA 13.4), WDDM |
| vBIOS | `94.02.74.00.01` |
| Power limit | 250 W (hard cap, read-only) |
| Max SM clock | 2100 MHz |
| Max memory clock | 9501 MHz |
| Display | Disabled (no outputs; desktop runs on the iGPU Vega 8) |
| PCIe (current) | **Gen1 × 4** — see below |
| GPU UUID | `GPU-7135d50d-97da-a0c8-3652-bf3494f0f14f` |

**Hardware caveat (as of Chapter 1).** The power-delivery capacitors around the core are **not
soldered** on this card at the time of measuring. The owner plans to re-solder them in a future
chapter. All numbers in this repository were measured **without** those capacitors; the moment
they are soldered, this note becomes a chapter of its own with fresh measurements.

**PCIe state: locked to Gen1 × 4.** This card currently runs *without* the PCIe unlock
procedure (a separate future chapter). In this state the device reports Gen1 as its link
capability max, so the link negotiates at **Gen1 × 4** at all times, even on a motherboard whose
host supports Gen3/Gen4. That is roughly **1 GB/s**, versus 16 GB/s for Gen3 × 16 the previous
card used. This single fact drives every number below.

Full `nvidia-smi -q` dump: `results/raw/hardware-cmp90hx.txt`.\n\n**Observed idle state (1 Nov 01:46, server loaded, no inference).** Memory clock stays at
**9501 MHz — the max — even in idle**, performance state stays at P0, power 78.6 W (limit 250 W),
temp 56 °C. This card never lowers memory clock or enters a low P-state on its own; idle power is
high by design. Live snapshot: `results/raw/gpu-idle-live-cmp90hx.txt`.

### Strata baseline (fast config)

Same fast configuration that produced the published 3060 numbers, used unchanged on this card
the first time:

- model Qwen3.8-Flash-Next IQ3_XXS (two GGUF parts), `--expert-cache auto`, `--prefill 7168`,
  `--spec 4`, `--kv q4_0`, `--kv-resident 32768`, `--vram-reserve-mib 1200`, `--spec-min-p 0.5`,
  `STRATA_ROUTE_PRIOR=1.5`, `--max-context 262144`, vision on, port 8090.
- expert cache on 10 GB: **783 slots, 1.29 GiB of VRAM** (the same config kept **2096 slots** on the
  12 GB card); KV streaming keeps 32 768 of 262 144 cells resident; expert arena 39.97 GiB in RAM,
  27 GiB pinned in 35 slices. VRAM after load: 8779 MiB used, 878 MiB free of 10 240 MiB.

Measurements are taken from the **engine log** (server flushes HTTP content in waves, so the
HTTP stream would over-report). One run each, server otherwise idle. Bench script:
`python scripts/bench.py http://127.0.0.1:8090 OUT.json strata-iq3_xxs-10gb.log`.

| Metric | CMP 90HX (10 GB) | RTX 3060 12 GB (ref) |
|---|---|---|
| Decode, 256 tokens | **35.6 tok/s** | 61.0 |
| Code, 256 tokens | **38.0 tok/s** | 63.1 |
| Prefill, 7063 tokens | **34.0 tok/s** | 618.6 → 756.5 (unlocked) |

The 3060 column is only a reference from the separate repo (different card, different PCIe link);
use it to see how far the *link* drags this card down, not as an apples-to-apples comparison.

### Why it is slow — the PCIe lock, measured

`results/raw/gpu-power-cmp90hx-baseline.csv` sampled the card every 2 s during the whole bench
(206 samples; 115 of them with util > 50 %):

| Sampled during load (util > 50 %) | Value |
|---|---|
| PCIe link | **Gen1 × 4 in 115 of 115 load samples** (487 of 487 total) |
| Power | median **102 W**, max 171 W, limit 250 W |
| SM clock | median 1860 MHz, peak 1875 MHz (cap 2100) |
| Temp | up to ~60 °C |

The card never actually exerts itself: it idles around 250 W of possible power and even the fixed
250 W limit is never approached, because prefill/decode stream expert weights from the CPU arena
over a ribbon that moves ~1 GB/s. The bottleneck is the link, not the silicon. GA102's tensor
throughput is far above GA106's; it simply cannot be fed.

### What is measured next

1. **PCIe unlock** of this card (raise the link above Gen1 × 4) and re-measure the same bench —
   this is the headline question for the card.
2. **Solder the missing power capacitors** and re-check stability and clocks under load.
3. **GEMM proof on GA102** (the same harness we ran on the 3060) with the Strata server stopped.
4. Idle-server sweeps on the 10 GB config (vram-reserve, expert-cache size).
5. **Application tests** — see the app log below.

---

## Application test log

The card is tested across applications; each row is its own chapter once published.

| Date | Application | Backend | Result | Files |
|---|---|---|---|---|
| 1 Nov 2026 | Strata (serve) | engine 0.1.54, IQ3_XXS | decode 35.6, prefill 34.0 tok/s (Gen1 × 4) | `results/raw/bench-cmp90hx-10gb-baseline.json` |

Planned: more LLM runtimes, and other workloads, in later chapters.

---

## Reproduce

1. Start the server with the 10 GB config (a visible console window):
   `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-server-visible-cmp.ps1`
2. Wait for `READY` on `http://127.0.0.1:8090/v1/models` (n_ctx 262144).
3. Measure: `python scripts/bench.py http://127.0.0.1:8090 OUT.json strata-iq3_xxs-10gb.log`
4. Sample the GPU during the run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sample-cmp.ps1 -Out OUT.csv -Seconds 420`

Configs: `scripts/strata-iq3_xxs-10gb.json`, restart helper `scripts/restart-cmp90hx.ps1`.

## License
Text and measurements are MIT (see the 3060 repo for the full text). Raw data stays in `results/raw/.
