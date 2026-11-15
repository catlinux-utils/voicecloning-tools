# OmniVoice on Vulkan

Zero-shot voice-cloning TTS for 600+ languages, running entirely on **Vulkan** — no CUDA, no ROCm/HIP,
no PyTorch, no external drivers or SDKs.

- **Model**: [OmniVoice](https://github.com/k2-fsa/OmniVoice) by k2-fsa (Apache-2.0) — zero-shot TTS,
  voice cloning, and voice design in 600+ languages.
- **Engine**: [audio.cpp](https://github.com/0xShug0/audio.cpp) v0.9.5 — pure C++/GGML inference with a
  Vulkan backend (Apache-2.0).
- **Setup**: checksum-pinned, idempotent installers for Windows, Linux, and Nix.
  Everything installs into this folder and uses only the Vulkan runtime that ships with your GPU driver.

**Contents**: [Requirements](#requirements) · [Quick start](#quick-start) · [Install](#install) ·
[Usage](#usage) · [Server](#server) · [Performance](#performance) · [Troubleshooting](#troubleshooting) ·
[Upgrading](#upgrading) · [Repository layout](#repository-layout) · [License & credits](#license--credits)

## Requirements

| | |
|---|---|
| OS | Windows 10+ x64, or Linux x64 |
| GPU | Any Vulkan-capable GPU (AMD, NVIDIA, Intel Arc). AMD on Linux: the stock mesa RADV driver is enough |
| Software | Windows: PowerShell 5.1+ · Linux: bash, curl, tar, sha256sum, python3 · Nix: any flake-enabled Nix |
| Disk | ~4 GB (85 MB runtime + 1.35 GB model + generated audio) |

## Quick start

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File setup.ps1
tts.bat "Hello world, this is OmniVoice on Vulkan." output\hello.wav
```

```bash
# Linux
./setup.sh
./tts.sh "Hello world, this is OmniVoice on Vulkan." output/hello.wav
```

```bash
# Nix (nothing is installed; runs from the store)
nix run . -- --text "Hello world." --out out.wav
```

The setup command downloads the two pinned artifacts, **verifies their SHA-256 checksums**, and installs
them. It is idempotent — re-running skips anything already installed and valid.

## Install

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1                 # full install
powershell -ExecutionPolicy Bypass -File setup.ps1 -SmokeTest      # + device check and sample generation
powershell -ExecutionPolicy Bypass -File setup.ps1 -SkipModel      # runtime only
powershell -ExecutionPolicy Bypass -File setup.ps1 -ModelPrecision f16   # q8_0 (default) | bf16 | f16
powershell -ExecutionPolicy Bypass -File setup.ps1 -Force          # re-download everything
```

### Linux

```bash
./setup.sh                      # full install
./setup.sh --smoke-test         # + device check and sample generation
./setup.sh --skip-model         # runtime only
./setup.sh --precision f16      # q8_0 (default) | bf16 | f16
./setup.sh --force              # re-download everything
```

If `--smoke-test` device listing shows no GPU, install the Vulkan loader and driver:

| Distribution | Packages |
|---|---|
| Debian / Ubuntu | `sudo apt install libvulkan1 mesa-vulkan-drivers` |
| Fedora | `sudo dnf install vulkan-loader mesa-vulkan-drivers` |
| Arch | `sudo pacman -S vulkan-radeon` (or `nvidia-utils`, `intel-media-driver`) |

### Nix

```bash
nix run . -- --text "Hello" --out out.wav   # TTS (q8_0, Vulkan backend)
nix run .#omnivoice-server                  # WebUI at http://127.0.0.1:8080
nix build .#omnivoice-f16                   # other precisions
```

Once the repo is on GitHub this also works from anywhere:
`nix run github:<you>/omnivoice-vulkan -- --text "..."`. The flake consumes the same
[`versions.json`](versions.json) pins via `fetchurl` SRI hashes, patches the prebuilt binaries for the Nix
store (`autoPatchelfHook` + `vulkan-loader`), and exposes `omnivoice`, `audiocpp-cli`, and
`omnivoice-server`. x86_64-linux only — the only prebuilt audio.cpp Linux target.

### Pinned artifacts

| Artifact | Version | Source |
|---|---|---|
| audio.cpp runtime, Vulkan portable (Windows x64 + Linux x64) | 0.9.5 | GitHub release `0xShug0/audio.cpp@v0.9.5` |
| OmniVoice GGUF `q8_0` (default), `bf16`/`f16` optional (1.35 / 1.64 GB) | HF revision `ca0b203e` | [`audio-cpp/audio.cpp-gguf`](https://huggingface.co/audio-cpp/audio.cpp-gguf) |

All versions, URLs, sizes, and checksums (SHA-256 + SRI) live in [`versions.json`](versions.json) — the
single source of truth shared by `setup.ps1`, `setup.sh`, and `flake.nix`. A checksum mismatch fails
loudly instead of silently installing something different.

> **Offline install**: copy `bin/` and `models/OmniVoice-GGUF/` from a machine where the setup script
> already ran. The pinned checksums are what make such copies trustworthy.

## Usage

Launchers exist for both platforms and behave identically:

| Task | Windows | Linux |
|---|---|---|
| TTS (auto voice) | `tts.bat "Text" [out.wav]` | `./tts.sh "Text" [out.wav]` |
| Voice cloning | `clone.bat "Text" ref.wav [out.wav] ["transcript"]` | `./clone.sh "Text" ref.wav [out.wav] ["transcript"]` |
| Voice design | `design.bat "Text" "attributes" [out.wav]` | `./design.sh "Text" "attributes" [out.wav]` |
| WebUI + API | `server.bat` | `./server.sh` |

```bash
# examples
tts.bat "Hello world, this is OmniVoice on Vulkan." output\hello.wav
clone.bat "Now I sound like the reference." sample.wav output\cloned.wav "transcript of sample.wav"
design.bat "A brand new voice." "female, young adult, low pitch, british accent" output\designed.wav
```

Output WAVs land in `output/` by default (24 kHz, 16-bit mono PCM).

### Direct CLI

```bash
bin/audiocpp_cli --task tts --family omnivoice --model models/OmniVoice-GGUF \
  --backend vulkan --text "..." --out out.wav --metrics        # Linux (Windows: bin\audiocpp_cli.exe, ^ line joins)
```

- **Clone**: add `--voice-ref ref.wav --reference-text "transcript"`. `--reference-text` is optional but
  improves quality — without it the model has to guess the transcript.
- **Design**: add `--instruct "attributes"`. The parser only accepts a fixed attribute vocabulary
  (gender, age, pitch, accent, style terms like "calm"); free-form phrases fail with
  `unsupported OmniVoice instruct items`.
- `--metrics` prints `rtf` (real-time factor, lower is better) and memory stats.
- `--device 1` targets the second Vulkan device (e.g. the integrated GPU instead of the dGPU).

### Request options

| Option | Default | Notes |
|---|---|---|
| `--num-inference-steps` | 32 | lower = faster, slightly less stable audio |
| `--guidance-scale` | 2.0 | classifier-free guidance strength |
| `--language` | auto | e.g. `en`, `de`, `zh` |
| `--seed` | random | reproducible output |
| `--request-option speed=1.2` | 1.0 | speech speed multiplier |
| `--mode streaming --text-chunk-size 160` | off | pseudo-streaming, chunks written to `--out-dir` |

Non-verbal tags go inline in the text: `[laughter]`, `[sigh]`, `[question-en]`, `[surprise-ah]`.

### Memory and precision

| Goal | Flag |
|---|---|
| Lower VRAM | `--load-option omnivoice.mem_saver=true` (some speed cost) |
| Faster attention | `--load-option perf_mode=flash_attention` (cannot combine with mem_saver) |
| Higher precision | install the `bf16`/`f16` GGUF instead of `q8_0` (see install flags) |

## Server

`server.bat` / `server.sh` starts `audiocpp_server` with [`server.json`](server.json):

- **WebUI**: <http://127.0.0.1:8080> — built-in TTS front-end.
- **API**: `POST /v1/audio/speech` (OpenAI-compatible):

```bash
curl -X POST http://127.0.0.1:8080/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"model":"omnivoice","input":"Hello from the API.","response_format":"wav"}' \
  -o out.wav
```

Cloning via API: add `"voice": "<path-or-uploaded-ref>"` and `"reference_text": "..."`.
Design via API: `"options": {"instruct": "female, ..."}`.

## Performance

Measured during this repo's setup on an **AMD Radeon RX 6600** (8 GB), short sentences, default settings:

| Task | Real-time factor | Meaning |
|---|---|---|
| TTS (auto voice) | ~0.55–0.69 | 1.5–1.8× faster than real time |
| Voice cloning | ~0.86 | ~1.2× faster than real time |
| Voice design | ~0.62 | 1.6× faster than real time |

Output is 24 kHz, 16-bit mono PCM WAV. First run per session is slower (shader/pipeline warm-up); later
generations are faster. For reference, upstream audio.cpp reports ~0.15 s for a 9-word clone on an
RTX 4090 with flash attention.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `unsupported OmniVoice instruct items: '...'` | Use only supported attribute words (gender, age, pitch, accent, "calm"); drop free-form phrases |
| Device listing shows no GPU | Driver/Vulkan issue — update GPU drivers on Windows; install `libvulkan1` + mesa/NVIDIA Vulkan driver on Linux (see install section) |
| `Checksum mismatch` during setup | Upstream artifact changed; do not ignore — compare with the release notes and update `versions.json` deliberately |
| First generation is slow | Normal: shaders compile once per session; subsequent runs are faster |
| Out of memory on small GPUs | Use `omnivoice.mem_saver=true`, or fewer `--num-inference-steps`; upstream runs OmniVoice on 4 GB-class GPUs (tested on Arc A310 4 GB) |
| `audiocpp_cli` does not start on Linux (missing `.so`) | Report it — the flake path auto-patches; for `setup.sh` installs add the missing library or switch to `nix run` |

## Upgrading

1. Bump the relevant entries in [`versions.json`](versions.json) (version, URL, size, SHA-256/SRI).
2. Re-run the setup script — new artifacts are downloaded and verified; stale ones are replaced.

Nothing else in the repo needs to change; launchers and configs reference `bin/` and `models/` paths only.

## Repository layout

| Path | Contents |
|---|---|
| `setup.ps1` | Reproducible installer, Windows (checksum-verified, idempotent) |
| `setup.sh` | Reproducible installer, Linux x64 (same pins, same logic) |
| `flake.nix` | Nix package: runtime + model + `omnivoice` / `omnivoice-server` wrappers |
| `versions.json` | Pinned versions, URLs, SHA-256 + SRI checksums — single source of truth |
| `tts` / `clone` / `design` / `server` `.bat` + `.sh` | One-line launchers (`--backend vulkan` preconfigured) |
| `server.json` | Server config (Vulkan, offline TTS, WebUI enabled) |
| `bin/`, `models/`, `output/` | Runtime, GGUF model, generated WAVs — installed by the setup script, gitignored |

The large binaries are intentionally **not** committed — the checksum-pinned installer is the
reproducibility mechanism.

## License & credits

- This installer/launcher harness: MIT — see [LICENSE](LICENSE). No third-party binaries are committed.
- [audio.cpp](https://github.com/0xShug0/audio.cpp) by 0xShug0: Apache-2.0.
- [OmniVoice](https://github.com/k2-fsa/OmniVoice) by k2-fsa: Apache-2.0.
- GGUF conversions: [`audio-cpp/audio.cpp-gguf`](https://huggingface.co/audio-cpp/audio.cpp-gguf);
  weights keep the upstream Apache-2.0 license. Full bundled-component list: `docs/model_licenses.md`
  inside the audio.cpp release.

To use other audio.cpp models beyond OmniVoice, the package specs live in `bin/model_specs/*.json`
after install.
