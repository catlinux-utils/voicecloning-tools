# OmniVoice on Vulkan

[OmniVoice](https://github.com/k2-fsa/OmniVoice) (k2-fsa) zero-shot voice-cloning TTS for 600+ languages,
running on **[audio.cpp](https://github.com/0xShug0/audio.cpp)** — a pure C++/GGML inference engine — using
the **Vulkan backend only**.

No CUDA, no ROCm/HIP, no PyTorch, no external drivers or SDKs. Everything uses the Vulkan runtime that
ships inside your normal GPU driver. Verified on **AMD Radeon RX 6600** (~1.5× faster than real-time);
works on any Vulkan-capable GPU (NVIDIA, Intel Arc, AMD).

## Reproducible install

Requirements: Windows 10+ x64, PowerShell 5.1+, ~4 GB free disk, a GPU with up-to-date Vulkan drivers.

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
```

That single command downloads the two pinned artifacts, **verifies their SHA-256 checksums**, extracts the
runtime to `bin\`, and installs the model to `models\`. It is idempotent — re-running it skips anything
already installed and valid.

Options:

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1 -SmokeTest          # also run a device check + generation
powershell -ExecutionPolicy Bypass -File setup.ps1 -SkipModel          # runtime only (no 1.35 GB model)
powershell -ExecutionPolicy Bypass -File setup.ps1 -ModelPrecision f16 # bf16/f16 instead of q8_0
powershell -ExecutionPolicy Bypass -File setup.ps1 -Force              # re-download everything
```

All versions, URLs, sizes, and checksums live in one file: [`versions.json`](versions.json). To upgrade,
bump the values there and re-run `setup.ps1`; a checksum mismatch fails loudly instead of silently
installing something different.

### What gets pinned

| Artifact | Version | Source |
|---|---|---|
| audio.cpp runtime (Windows x64, Vulkan portable) | 0.9.5 | GitHub release `0xShug0/audio.cpp@v0.9.5` |
| OmniVoice GGUF `q8_0` (default), `bf16`/`f16` optional | @ HF revision `ca0b203e` | `audio-cpp/audio.cpp-gguf` on Hugging Face |

> **Offline install**: copy `bin\` + `models\OmniVoice-GGUF\` from any machine where `setup.ps1` already
> ran — the checksums in `versions.json` are what makes such copies trustworthy.

## Usage

```bat
:: plain text-to-speech (auto voice)
tts.bat "Hello world, this is OmniVoice on Vulkan." output\hello.wav

:: voice cloning — copy a voice from a wav (a few seconds of clean speech is enough)
clone.bat "Now I sound like the reference." sample.wav output\cloned.wav "transcript of sample.wav"

:: voice design — describe the voice with attributes
design.bat "A brand new voice." "female, young adult, low pitch, british accent" output\designed.wav

:: web UI + OpenAI-compatible API
server.bat        :: WebUI at http://127.0.0.1:8080
```

Sample outputs from the original install are not committed; generate your own with the commands above or
`setup.ps1 -SmokeTest`.

## Direct CLI usage

```bat
bin\audiocpp_cli.exe --task tts --family omnivoice --model models\OmniVoice-GGUF ^
  --backend vulkan --text "..." --out out.wav --metrics
```

- **Clone**: add `--voice-ref ref.wav --reference-text "transcript"` (`--reference-text` is optional but
  improves quality; without it the model has to guess the transcript).
- **Design**: add `--instruct "attributes"` — the parser only accepts a fixed vocabulary
  (gender, age, pitch, accent, style terms like "calm"; free-form phrases fail with
  `unsupported OmniVoice instruct items`).
- `--metrics` prints `rtf` (real-time factor, lower is better); ~0.6–0.9 RTF measured on RX 6600.
- `--device 1` targets the second Vulkan device (e.g. the integrated GPU instead of the dGPU).

### Useful request options

| Option | Default | Notes |
|---|---|---|
| `--num-inference-steps` | 32 | lower = faster, slightly less stable audio |
| `--guidance-scale` | 2.0 | classifier-free guidance strength |
| `--language` | auto | e.g. `en`, `de`, `zh` |
| `--seed` | random | reproducible output |
| `--request-option speed=1.2` | 1.0 | speech speed multiplier |
| `--mode streaming --text-chunk-size 160` | off | pseudo-streaming, chunks to `--out-dir` |

Non-verbal tags go inline in the text: `[laughter]`, `[sigh]`, `[question-en]`, `[surprise-ah]`.

### Low-VRAM / quality options

- `--load-option omnivoice.mem_saver=true` — lower VRAM at some speed cost.
- `--load-option perf_mode=flash_attention` — faster attention (cannot combine with mem_saver).
- Other GGUF precisions via `setup.ps1 -ModelPrecision f16` (or `bf16`), 1.64 GB each.

## Server

`server.bat` starts `audiocpp_server.exe` with the config in `server.json`:

- **WebUI**: <http://127.0.0.1:8080> — built-in TTS front-end.
- **API**: `POST /v1/audio/speech` (OpenAI-compatible):

```bash
curl -X POST http://127.0.0.1:8080/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"model":"omnivoice","input":"Hello from the API.","response_format":"wav"}' \
  -o out.wav
```

Cloning via API: add `"voice": "<path-or-uploaded-ref>"` and `"reference_text": "..."`;
design via API: `"options": {"instruct": "female, ..."}`.

## Repository layout

```
setup.ps1              reproducible installer (checksum-verified, idempotent)
versions.json          pinned versions, URLs, SHA-256 checksums — single source of truth
tts.bat / clone.bat    one-line launchers (call bin\audiocpp_cli.exe --backend vulkan)
design.bat / server.bat
server.json            server config (Vulkan, offline TTS, WebUI enabled)
bin/                   audio.cpp runtime          (installed by setup.ps1, gitignored)
models/                OmniVoice GGUF            (installed by setup.ps1, gitignored)
output/                generated WAV files       (gitignored)
```

The large binaries are intentionally **not** committed — the checksum-pinned installer is the
reproducibility mechanism.

## Notes

- First run per session is slower (shader/pipeline warm-up); later generations are faster.
- audio.cpp is Apache-2.0; OmniVoice weights are Apache-2.0 (k2-fsa). This harness is MIT — see
  [LICENSE](LICENSE). GGUF conversions: `audio-cpp/audio.cpp-gguf` on Hugging Face.
- To add other audio.cpp models later, package specs live in `bin\model_specs\*.json`.

## Publishing to GitHub

```bash
git init                       # already done if you cloned/committed this
git add -A && git commit -m "OmniVoice on Vulkan"
git remote add origin git@github.com:<you>/omnivoice-vulkan.git
git push -u origin main
```
