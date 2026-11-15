#!/usr/bin/env bash
# Usage: ./clone.sh "Text to speak" ref.wav [output.wav] ["transcript of ref.wav"]
set -euo pipefail
cd "$(dirname "$0")"
if [ $# -lt 2 ]; then
    echo 'Usage: ./clone.sh "Text to speak" ref.wav [output.wav] ["transcript of ref.wav"]' >&2
    exit 1
fi
OUT="${3:-output/cloned.wav}"
mkdir -p output
ARGS=(--voice-ref "$2")
if [ $# -ge 4 ]; then
    ARGS+=(--reference-text "$4")
fi
exec bin/audiocpp_cli --task tts --family omnivoice --model models/OmniVoice-GGUF \
    --backend vulkan --text "$1" "${ARGS[@]}" --out "$OUT" --metrics
