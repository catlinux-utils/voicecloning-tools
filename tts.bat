@echo off
rem Usage: tts.bat "Text to speak" [output.wav]
setlocal
if "%~1"=="" (
    echo Usage: tts.bat "Text to speak" [output.wav]
    exit /b 1
)
set "OUT=%~2"
if "%OUT%"=="" set "OUT=output\generated.wav"
if not exist output mkdir output
"%~dp0bin\audiocpp_cli.exe" --task tts --family omnivoice --model "%~dp0models\OmniVoice-GGUF" --backend vulkan --text "%~1" --out "%OUT%" --metrics
