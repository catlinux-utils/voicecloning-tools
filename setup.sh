#!/usr/bin/env bash
# Reproducible installer for OmniVoice-on-Vulkan (Linux x86_64).
# Downloads the pinned, checksummed artifacts from versions.json and installs them.
#
# Usage (from the repository root):
#   ./setup.sh                        # full install
#   ./setup.sh --skip-model           # runtime only
#   ./setup.sh --smoke-test           # install + device check + sample generation
#   ./setup.sh --force                # re-download even if cached
#   ./setup.sh --precision f16        # q8_0 (default) | bf16 | f16
#
# Requires: bash, curl, tar, sha256sum, python3, ~4 GB free disk.
# GPU: any Vulkan-capable GPU with an installed driver (AMD: mesa RADV is enough;
# no ROCm, no proprietary compute stack). Windows: use setup.ps1 instead.

set -euo pipefail
cd "$(dirname "$0")"

SKIP_MODEL=0
SMOKE_TEST=0
FORCE=0
PRECISION="q8_0"
PLATFORM="linux-x64"
CACHE=".cache/downloads"
STAMP="bin/.setup-stamp.json"

usage() {
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-model) SKIP_MODEL=1 ;;
        --smoke-test) SMOKE_TEST=1 ;;
        --force) FORCE=1 ;;
        --precision)
            [ $# -ge 2 ] || { echo "--precision needs an argument" >&2; exit 1; }
            PRECISION="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

case "$PRECISION" in
    q8_0|bf16|f16) ;;
    *) echo "invalid --precision '$PRECISION' (use q8_0, bf16 or f16)" >&2; exit 1 ;;
esac

for tool in curl tar sha256sum python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "required tool missing: $tool" >&2; exit 1; }
done

mkdir -p "$CACHE" bin

sha256_of() { sha256sum "$1" | cut -d' ' -f1; }

# Read an asset dict out of versions.json and emit KEY=VALUE shell assignments.
# $1 is a Python expression evaluated against the `versions` dict (values here
# are only ever built from the whitelisted PLATFORM/PRECISION cases above).
read_spec() {
python3 - "$1" <<'PY'
import json, shlex, sys
versions = json.load(open("versions.json"))
spec = eval(sys.argv[1], {"versions": versions})
for key in ("filename", "url", "sha256"):
    print(f"{key.upper()}={shlex.quote(spec[key])}")
PY
}

# fetch <dest> <url> <sha256> <label>
fetch() {
    local dest="$1"
    if [ "$FORCE" -ne 1 ] && [ -f "$dest" ] && [ "$(sha256_of "$dest")" = "$3" ]; then
        echo "[ok] $4 already cached (checksum matches)"
        return 0
    fi
    echo "[..] downloading $4"
    curl -sSL --fail -o "$dest" "$2"
    local actual
    actual="$(sha256_of "$dest")"
    if [ "$actual" != "$3" ]; then
        echo "Checksum mismatch for $4:" >&2
        echo "  expected: $3" >&2
        echo "  actual:   $actual" >&2
        echo "The upstream artifact may have changed; update versions.json if intentional." >&2
        exit 1
    fi
    echo "[ok] $4 downloaded (checksum matches)"
}

MODEL_DIR="models/$(python3 -c 'import json; print(json.load(open("versions.json"))["omnivoice_gguf"]["dir"])')"

echo "=== OmniVoice on Vulkan - setup ==="
echo "audio.cpp $(python3 -c 'import json; print(json.load(open("versions.json"))["audio_cpp"]["version"])') | platform $PLATFORM | model precision $PRECISION"

# --- 1. Runtime (audio.cpp portable Vulkan build) ---
eval "$(read_spec "versions['audio_cpp']['assets']['$PLATFORM']")"
RUNTIME_OK=0
if [ "$FORCE" -ne 1 ] && [ -f "$STAMP" ]; then
    stamp_sha="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("runtime_sha256",""))' "$STAMP" 2>/dev/null || true)"
    [ "$stamp_sha" = "$SHA256" ] && { echo "[ok] runtime already installed (checksum matches)"; RUNTIME_OK=1; }
fi
if [ "$RUNTIME_OK" -ne 1 ]; then
    fetch "$CACHE/$FILENAME" "$URL" "$SHA256" "audio.cpp runtime ($PLATFORM)"
    echo "[..] extracting runtime -> bin/"
    tmp="$CACHE/extract-runtime"
    rm -rf "$tmp" && mkdir -p "$tmp"
    tar -xzf "$CACHE/$FILENAME" -C "$tmp"
    # handle both flat tarballs and ones with a top-level directory
    if [ -f "$tmp/audiocpp_cli" ]; then
        cp -a "$tmp/." bin/
    else
        inner="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)"
        [ -n "$inner" ] || { echo "unexpected tarball layout" >&2; exit 1; }
        cp -a "$inner/." bin/
    fi
    rm -rf "$tmp"
    python3 - "$SHA256" >"$STAMP" <<'PY'
import datetime, json, sys
print(json.dumps({
    "runtime_sha256": sys.argv[1],
    "platform": "linux-x64",
    "installed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}))
PY
    echo "[ok] runtime installed"
fi

# --- 2. Model (OmniVoice GGUF) ---
if [ "$SKIP_MODEL" -ne 1 ]; then
    eval "$(read_spec "versions['omnivoice_gguf']['precision']['$PRECISION']")"
    mkdir -p "$MODEL_DIR"
    MODEL_DEST="$MODEL_DIR/$FILENAME"
    MODEL_OK=0
    if [ "$FORCE" -ne 1 ] && [ -f "$MODEL_DEST" ]; then
        if [ "$(sha256_of "$MODEL_DEST")" = "$SHA256" ]; then
            echo "[ok] model already installed (checksum matches)"
            MODEL_OK=1
        else
            echo "[..] installed model failed checksum, re-downloading"
        fi
    fi
    if [ "$MODEL_OK" -ne 1 ]; then
        fetch "$CACHE/$FILENAME" "$URL" "$SHA256" "OmniVoice $PRECISION model"
        mv "$CACHE/$FILENAME" "$MODEL_DEST"
        [ "$(sha256_of "$MODEL_DEST")" = "$SHA256" ] || { echo "Model install failed final checksum" >&2; exit 1; }
        echo "[ok] model installed -> $MODEL_DEST"
    fi
fi

# --- 3. Smoke test ---
CLI="bin/audiocpp_cli"
if [ "$SMOKE_TEST" -eq 1 ]; then
    [ -x "$CLI" ] || { echo "audiocpp_cli not found after install" >&2; exit 1; }
    echo "[..] smoke test: device listing"
    "$CLI" --list-devices || { echo "Device listing failed" >&2; exit 1; }
    if [ "$SKIP_MODEL" -ne 1 ]; then
        echo "[..] smoke test: generating sample (this loads the model, ~30 s first run)"
        "$CLI" --task tts --family omnivoice \
            --model "$MODEL_DEST" --backend vulkan \
            --text 'OmniVoice setup smoke test passed.' \
            --out "$CACHE/smoke.wav" --metrics || { echo "Smoke test generation failed" >&2; exit 1; }
        echo "[ok] smoke sample written to $CACHE/smoke.wav"
    fi
fi

echo "=== done ==="
if [ "$SKIP_MODEL" -ne 1 ]; then
    echo 'Try:  ./tts.sh "Hello world."   or   ./server.sh  (WebUI at http://127.0.0.1:8080)'
fi
if ! command -v vulkaninfo >/dev/null 2>&1; then
    echo "note: 'vulkaninfo' not found. If --list-devices shows no GPU, install the Vulkan loader + driver:"
    echo "  Debian/Ubuntu: sudo apt install libvulkan1 mesa-vulkan-drivers"
    echo "  Fedora:        sudo dnf install vulkan-loader mesa-vulkan-drivers"
    echo "  Arch:          sudo pacman -S vulkan-radeon   # or nvidia-utils / intel-media-driver"
fi
