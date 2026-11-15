#!/usr/bin/env bash
# Usage: ./tts.sh "Text to speak" [output.wav]
set -euo pipefail
cd "$(dirname "$0")"
if [ $# -lt 1 ]; then
    echo 'Usage: ./tts.sh "Text to speak" [output.wav]' >&2
    exit 1
fi
OUT="${2:-output/generated.wav}"
mkdir -p output
exec bin/audiocpp_cli --task tts --family omnivoice --model models/OmniVoice-GGUF \
    --backend vulkan --text "$1" --out "$OUT" --metrics
