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
| **CMP 90HX** | GA102, Ampere, sm_86, 80 SM | 10 GB GDDR6X, 760 GB/s | **Solder the missing power capacitors → PCIe unlock up to Gen2 × 16** (x4 → x16) | Chapter 1 baseline (Gen1 × 4, no caps) |
| **CMP 50HX** | TU102, Turing, sm_75, 3584 cores | 10 GB GDDR6, 560 GB/s | **Memory upgrade to 20 GB** (+ the same capacitor/PCIe unlock) | Not installed yet |

The mods are planned, not performed. Every number in this repository is labelled with the
hardware state it was measured in, and future chapters re-measure after each change:

- **Chapter 2** — 90HX with soldered capacitors: expect the PCIe link to rise from **Gen1 × 4** to
  **Gen2 × 16** (the device max), i.e. 4× the streaming bandwidth. All Chapter 1 numbers become the
  honest "before".
- **Chapter 3** — CMP 50HX arrives with **20 GB VRAM**: twice the expert-cache budget and far less
  PCIe dependence. It is a Turing (sm_75) card, so it inherits fewer of Strata's sm_80+ kernels,
  but 20 GB makes it the fleet's high-VRAM card for AI.

See the internet research behind this in `docs/CMP-BACKGROUND.md` (added in Chapter 2).

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
bottleneck here. Util pins at 100 % yet power stays around 115 W: an 80-SM GA102 is overkill and
mostly idle inside each layer, and the ~9.5 s/it is the backend's own cost for this int8 model at
1024 × 1024. That makes ComfyUI the worse workload to blame the link on — the headline stays the
capacitor/PCIe re-measure, not this app.

---

## Application test log

The card is tested across applications; each row is its own chapter once published.

| Date | Application | Backend | Result | Files |
|---|---|---|---|---|
| 1 Nov 2026 | Strata (serve) | engine 0.1.54, IQ3_XXS | decode 35.6, prefill 34.0 tok/s (Gen1 × 4) | `results/raw/bench-cmp90hx-10gb-baseline.json` |
| 1 Nov 2026 | ComfyUI (H3 fork) | torch 2.14 + cu130, Z-Image-Turbo int8, 1024² | t2i 8 steps ~76 s (~9.5 s/it), pipeline 97 s, Gen1 × 4 | `results/raw/comfyui-zimage-90hx-00002-seed12345.png`, CSV traces |

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
Text and measurements are MIT (see the 3060 repo for the full text). Raw data stays in `results/raw/`.
