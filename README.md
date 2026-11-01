# Strata on an NVIDIA CMP 90HX (GA102, 10 GB): the card's history

Our own measurements of [Strata](https://github.com/Niko1221/Strata) (engine 0.1.54, app 0.2.8)
running Qwen3.8-Flash-Next **IQ3_XXS** on a single **NVIDIA CMP 90HX** in a Ryzen 7 5700G desktop,
Windows 10. Every number in this repository was produced on that machine. Raw data is in
`results/raw/`, the scripts and configs that made it are in `scripts/`.

This repository is the running history of the card, updated chapter by chapter as we tune it and
test it in different applications. Chapter 1 (this file) is the hardware profile and the first
baseline. The previous card (RTX 3060 12 GB) has its own history:
[rtx3060-strata-tuning](https://github.com/ildargiv/rtx3060-strata-tuning).

## The fleet and the hardware roadmap

Two CMP cards are part of this history. Only the 90HX is installed and measured as of Chapter 1.

| Card | Architecture | Memory (stock) | Planned hardware mod | Measured |
|---|---|---|---|---|
| **CMP 90HX** | GA102, Ampere, sm_86, 50 SM / 6400 cores | 10 GB GDDR6X, 760 GB/s | **Compute unlock** (done, Ch. 3) + **solder the missing power capacitors → PCIe up to Gen2 × 16** (x4 → x16) | Ch. 1 baseline (Gen1 × 4), Ch. 3 unlocked |
| **CMP 50HX** | TU102, Turing, sm_75, 3584 cores | 10 GB GDDR6, 560 GB/s | **Memory upgrade to 20 GB** (+ the same capacitor/PCIe unlock) | Not installed yet |

The compute unlock is done; the hardware mods are still planned. Every number in this repository
is labelled with the hardware state it was measured in, and later chapters re-measure after each
change:

- **Compute unlock — done in Chapter 3.** The 90HX ships with eFuse-set SM issue-rate throttling,
  so a locked card reaches ~3 % of its silicon on compute-bound work. Removed with a community
  GSP unlock: **2.94 → 85.85 TH/s** on PearlHash. See `docs/CMP-UNLOCK.md`.
- **Soldered capacitors** — 90HX with the missing PCIe coupling capacitors fitted: expect the link
  to rise from **Gen1 × 4** to **Gen1 × 16**, and with the Gen2 retrain up to **Gen2 × 16** (the
  device max), i.e. 4–8× the streaming bandwidth. Every pre-solder number becomes the honest
  "before".
- **CMP 50HX arrives with 20 GB VRAM** — twice the expert-cache budget and far less PCIe
  dependence. It is a Turing (sm_75) card, so it inherits fewer of Strata's sm_80+ kernels, but
  20 GB makes it the fleet's high-VRAM card for AI.

See the internet research behind this in `docs/CMP-BACKGROUND.md` (Chapter 2) and
`docs/CMP-UNLOCK.md` (Chapter 3).

---

## Chapter 1 (1 Nov 2026): hardware profile and Strata baseline

### Hardware profile

| Field | Value |
|---|---|
| Product | NVIDIA CMP 90HX |
| Architecture | Ampere, GA102 (`220D-100-A1`), 50 SM / 6400 CUDA cores |
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

Full `nvidia-smi -q` dump: `results/raw/hardware-cmp90hx.txt`.

**Observed idle state (1 Nov 01:46, server loaded, no inference).** Memory clock stays at
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

## Chapter 2 (1 Nov 2026): ComfyUI on the 90HX — Z-Image turbo

The card's second application: ComfyUI. On this machine it lives as a specialised fork at
`D:\ComfyUI-h3` (tuned for MiniMax H3 / YuE2 / Z-Image / ACE-Step / Wan2.2, with **int8 convrot**
conversions in its `models/`), which is what the card runs here. Server: ComfyUI 0.36.0, Python
3.11.9, torch 2.14.0+cu130, CUDA 13.0, launched headless on `cuda:0`:

```
python main.py --listen 127.0.0.1 --port 8188 --disable-auto-launch --cuda-device 0
```

`/system_stats` reports `cuda:0 NVIDIA CMP 90HX` with ~9.6 GB of the 10 GB free.

### Fork quirk: stock graphs do not run

The first attempt used the classic `CheckpointLoaderSimple → KSampler` graph with the bundled
checkpoint (`yue2_3b_int8_convrot.safetensors`). The run fails in KSampler with
`ValueError: too many values to unpack (expected 3)`: the fork's models need their own loaders and
text encoders. The fork ships a working example, `workflows/zimage_turbo_smoketest.json`, which is
the graph used below.

### The working t2i graph (Z-Image-Turbo, int8)

| Node | Input | Value |
|---|---|---|
| UNETLoader | unet_name | `z_image_turbo_int8_convrot.safetensors` |
| CLIPLoader | clip_name / type | `qwen_3_4b.safetensors` / `stable_diffusion` |
| VAELoader | vae_name | `ae.safetensors` |
| TextEncodeZImageOmni | clip / prompt | same CLIP, t2i prompt |
| EmptyLatentImage | 1024 × 1024 | batch 1 |
| KSampler | euler / simple | cfg 1.0, steps 8, denoise 1.0 |
| VAEDecode → SaveImage | | prefix `cmp90hx_zimage` |

Note: the fork deduplicates identical prompts — resubmitting the same seed returns in ~0.5 s
without touching the GPU or writing a new file. Every timing below uses a fresh seed.

### Results (fresh seed 12345)

Timing is the honest full pipeline (submit → PNG on disk), run warm (models already loaded):

| Stage | Wall time |
|---|---|
| Full t2i pipeline, 1024 × 1024 | **97.2 s** |
| KSampler, 8 steps | ~76 s → **~9.5 s/it** |
| VAE decode + save (included above) | ~21 s |

The first (cold) run took 183 s, including ~42 s of model initialisation before step 1. Both
outputs are correct images from the prompt (a tabby cat on a windowsill) — the card computes, it
does not just stream. Outputs: `results/raw/comfyui-zimage-90hx-0000X-s*.png`; GPU traces:
`results/raw/gpu-power-comfy90hx-zimage-{1st,2nd}.csv`.

### GPU profile during generation (util > 50 %)

| Sampled during load | Value |
|---|---|
| PCIe link | **Gen1 × 4 in 100 % of load samples** (as in Chapter 1) |
| Utilisation | avg 96–100 % |
| Power | avg 111–114 W, max 117 W (limit 250 W) |
| SM clock | max 1860 MHz (cap 2100) |
| VRAM | peak 9.25–9.4 GB of 10.24 GB |

Unlike Strata, the whole 3B-int8 model fits in the 10 GB, so the PCIe lock is not the step-time
bottleneck here. Util pins at 100 % yet power stays around 115 W: a 50-SM GA102 (6400 cores) is
overkill for this model and mostly idle inside each layer, and the ~9.5 s/it is the backend's own
cost for this int8 model at 1024 × 1024. That makes ComfyUI the worse workload to blame the link
on — the headline stays the capacitor/PCIe re-measure, not this app.

**Re-read after Chapter 3:** the 115 W at 100 % utilisation was not the model's cost. It is the
same eFuse SM issue-rate throttle that Chapter 3 removes — the ALUs were starved, which is why a
"fully loaded" card sat at 46 % of its power limit. These ComfyUI numbers are therefore a
**locked-card baseline**; the unlocked step time is not measured yet.

---

## Chapter 3 (1 Nov 2026): Pearl (PRL) mining — and the compute unlock that changed the card

The third application was supposed to be a quick mining test. It turned into the most important
chapter so far: mining exposed the card's **eFuse SM issue-rate throttle** in a way no other
workload had, and removing it multiplied the card's compute by **29×**.

### Setup

| Field | Value |
|---|---|
| Miner | **SRBMiner-MULTI 3.8.3** (official release 2026-10-30, MD5 `ddcf99d3…a6e3` verified) |
| Pool | Kryptex, `prl.kryptex.network:7048`, algorithm **PearlHash** |
| Wallet / worker | own Pearl wallet (`prl1p…`), worker `cmp90hx` |
| Command | `SRBMiner-MULTI.exe --disable-cpu --algorithm-gpu pearlhash --pool prl.kryptex.network:7048 --wallet <prl1p…> --worker cmp90hx` |

Kryptex's compatibility table lists CMP cards only for PeakMiner and ForgeMiner, so a fallback was
prepared. It was not needed — SRBMiner detects the card correctly:

```
GPU1 [CUDA][0000:01:00.0] : nvidia_cmp_90hx [ampere] [CC: 8.6] [SM: 50] [10239 MB]
is CMP: TRUE | is SM_86 | memory bus width: 320 bit | driver 13.04
```

### Before the unlock

Two runs on the stock driver (616.92), 5 and 15 minutes:

| Metric | run 1 (5 min) | run 2 (15 min) |
|---|---|---|
| Hashrate | 2.80 TH/s | **2.94 TH/s** (15-min avg 2931 GH/s) |
| Power | 110.7 W | 110.7 W (limit 250 W) |
| SM clock | 1860 MHz | 1860 MHz, no dips |
| Temperature / fan | 49 °C / 32 % | 51 °C / 33 % |
| VRAM | 359 MB | 359 MB |
| PCIe | Gen1 × 4 in 100 % of samples | Gen1 × 4 in 100 % of samples |
| Shares | 0 accepted | 0 accepted |

**Zero shares was not a fault.** The pool's share difficulty works out to ≈ 51 PH: at 2.94 TH/s one
share takes about **4.8 hours**, so 20 minutes could not produce one. At the unlocked speed a share
arrives every ~10 minutes, which is exactly what happened below.

### The clue: 110 W at 100 % utilisation

Every sensor said the card was fine — 1860 MHz of 2100, 49 °C of 93 °C, 111 W of 250 W, utilisation
100 % — yet it produced 3 % of what its silicon should. The missing 97 % was not a damaged die:

| Same silicon, two algorithms | CMP 90HX | RTX 3080 (68 SM) |
|---|---|---|
| **Ethash** (memory-bound) | 86–98 MH/s | ~95–100 MH/s → **≈ 90 %** |
| **PearlHash** (compute-bound, BLAKE3) | **2.94 TH/s** | ~100 TH/s → **≈ 3 %** |

On memory-bound work the card is ~90 % of an RTX 3080; on compute-bound work it is 3 %. Memory is
untouched (760 GB/s, 9501 MHz = the GDDR6X rating). The only difference is dependence on SM issue
rate — which is exactly what the eFuse bits throttle. By SM count alone (50/68 × clock ratio) the
card should reach ~72 TH/s.

### The unlock

There is no NVIDIA "mining driver" — the limit lives in eFuse and cannot be patched from the VBIOS
(an RTX 3080 VBIOS cross-flash was tried and dies at GDDR6X memory training). The only route is the
GSP Falcon exploit (V67) that opens the PLM masks and writes the `FEAT_OVR` selectors.

Used here: the **Windows EFI bootloader** from
[`WildFlash1st/cmp90hx-unlock-for-windows`](https://github.com/WildFlash1st/cmp90hx-unlock-for-windows)
v3.05 — an unsigned EFI application on a USB stick that runs before the OS and chainloads Windows
with the card already unlocked. No driver replacement, no vBIOS flash. Secure Boot must be off.

Details, sources and the list of what does **not** work: `docs/CMP-UNLOCK.md`.

**It is volatile:** any full reboot (POST re-runs the VBIOS) restores the throttle, and the USB boot
has to be repeated. Rollback is therefore free — reboot and the card is stock.

### After the unlock

10-minute run, same miner, same pool, same command:

| Metric | Locked | Unlocked | Δ |
|---|---|---|---|
| **Hashrate** | 2.94 TH/s | **85.85 TH/s** (82.3–88.7) | **×29.2** |
| Power | 110.7 W | **249.3 W** (99.7 % of the 250 W cap) | ×2.25 |
| SM clock | 1860 MHz | **1735 MHz** (1710–1800) | −7 % |
| Efficiency | 26.6 GH/W | **344 GH/W** | ×12.9 |
| Temperature / fan | 51 °C / 33 % | **70.4 °C / 44 %** | +19 °C |
| VRAM | 359 MB | 320 MB | — |
| PCIe | Gen1 × 4 | Gen1 × 4 | unchanged |
| Shares | 0 in 20 min | **1 accepted** (69 ms) | — |

The first 90 s after the unlock actually read 90.06 TH/s; the card settles to ~86 TH/s as it heats
and the power governor engages. **85.85 TH/s is the steady-state number.**

### What the numbers say

1. **The hypothesis held exactly.** The estimate from SM count was ~72 TH/s; the card reached 86.
   Unlocked, it delivers **86 % of an RTX 3080** on PearlHash — the same ratio it already had on
   Ethash. The throttle only ever hit ALU-bound work; nothing was broken in the silicon.
2. **The bottleneck moved.** It used to be SM issue rate. Now it is the **250 W power limit**: the
   card draws 249.3 W of 250 and drops its own clock from 1860 to 1735 MHz to stay inside it. There
   is no software lever left — the limit is read-only and the memory clock is already at its rating.
3. **Efficiency is 344 GH/W** against 420 GH/W for an RTX 3080 — 82 % of the reference, while being
   clamped by a power cap the 3080 does not hit at 240 W.
4. **PCIe is irrelevant to mining.** Gen1 × 4 throughout, in every sample, before and after. The
   link only matters for Strata's expert streaming and tensor split — the capacitor mod remains a
   separate, still-unmeasured chapter.

### Why this chapter matters beyond mining

The same unlock is worth roughly **×8 on Strata's prefill** according to the project's own
llama.cpp benchmarks (224 → 1770 t/s), i.e. it attacks exactly the metric Chapter 1 showed being
dragged down by the link and by compute. Pearl was the cheapest way to prove the unlock works;
the LLM re-measurement is the one that pays off in daily use.

### Correction to Chapters 1–2

The 90HX is a **50-SM / 6400-core** GA102, not 80 SM. Corrected throughout; the "80-SM GA102"
phrasing in Chapter 2 was wrong, and the low power draw there is explained by the throttle, not by
the model being too small for the card.

---

## Application test log

The card is tested across applications; each row is its own chapter once published.

| Date | Application | Backend | Result | Files |
|---|---|---|---|---|
| 1 Nov 2026 | Strata (serve) | engine 0.1.54, IQ3_XXS | decode 35.6, prefill 34.0 tok/s (Gen1 × 4) | `results/raw/bench-cmp90hx-10gb-baseline.json` |
| 1 Nov 2026 | ComfyUI (H3 fork) | torch 2.14 + cu130, Z-Image-Turbo int8, 1024² | t2i 8 steps ~76 s (~9.5 s/it), pipeline 97 s, Gen1 × 4 | `results/raw/comfyui-zimage-90hx-00002-seed12345.png`, CSV traces |
| 1 Nov 2026 | Pearl (PRL) mining | SRBMiner-MULTI 3.8.3, PearlHash, Kryptex | locked **2.94 TH/s @ 110.7 W**; unlocked **85.85 TH/s @ 249.3 W** (×29.2) | `results/raw/pearl-srbminer-{run1,run2,post1,post2}-gpu.csv` |

Planned: more LLM runtimes, and other workloads, in later chapters.

---

## Reproduce

1. Start the server with the 10 GB config (a visible console window):
   `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-server-visible-cmp.ps1`
2. Wait for `READY` on `http://127.0.0.1:8090/v1/models` (n_ctx 262144).
3. Measure: `python scripts/bench.py http://127.0.0.1:8090 OUT.json strata-iq3_xxs-10gb.log`
4. Sample the GPU during the run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sample-cmp.ps1 -Out OUT.csv -Seconds 420`

Configs: `scripts/strata-iq3_xxs-10gb.json`, restart helper `scripts/restart-cmp90hx.ps1`.

### Pearl (PRL) mining test (Chapter 3)

1. Download SRBMiner-MULTI 3.8.3 (win64) and verify the MD5 against the release `.md5` file.
2. Run the timed test (the script starts the 1 s GPU sampler itself):
   `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-pearl-srbminer.ps1 -Wallet prl1p... -Seconds 600 -Tag post2`
3. Compare against the locked card: same command on a card that has **not** been unlocked through
   the EFI USB bootloader. A locked card draws ~111 W at 100 % utilisation and ~3 TH/s; an
   unlocked one saturates the 250 W limit and reaches ~86 TH/s.

The unlock itself is a separate, external step — see `docs/CMP-UNLOCK.md`.

## License
Text and measurements are MIT (see the 3060 repo for the full text). Raw data stays in `results/raw/`.
