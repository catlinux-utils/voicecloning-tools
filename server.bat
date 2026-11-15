@echo off
rem Starts the OmniVoice WebUI + OpenAI-compatible API on Vulkan.
rem WebUI:   http://127.0.0.1:8080
rem API:     POST /v1/audio/speech
"%~dp0bin\audiocpp_server.exe" --config "%~dp0server.json"
