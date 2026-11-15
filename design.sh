#!/usr/bin/env bash
# Usage: ./design.sh "Text to speak" "female, young adult, low pitch" [output.wav]
# Attributes must come from the supported vocabulary: gender, age, pitch, accent, ...
set -euo pipefail
cd "$(dirname "$0")"
if [ $# -lt 2 ]; then
    echo 'Usage: ./design.sh "Text to speak" "instruct attributes" [output.wav]' >&2
    exit 1
fi
OUT="${3:-output/designed.wav}"
mkdir -p output
exec bin/audiocpp_cli --task tts --family omnivoice --model models/OmniVoice-GGUF \
    --backend vulkan --text "$1" --instruct "$2" --out "$OUT" --metrics
