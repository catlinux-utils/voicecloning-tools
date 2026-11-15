#!/usr/bin/env bash
# Starts the OmniVoice WebUI + OpenAI-compatible API on Vulkan (Linux).
# WebUI:   http://127.0.0.1:8080
# API:     POST /v1/audio/speech
set -euo pipefail
cd "$(dirname "$0")"
exec bin/audiocpp_server --config server.json
