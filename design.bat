@echo off
rem Usage: design.bat "Text to speak" "female, young adult, low pitch" [output.wav]
rem Attributes must come from the supported vocabulary: gender, age, pitch, accent, ...
setlocal
if "%~1"=="" goto :usage
if "%~2"=="" goto :usage
set "OUT=%~3"
if "%OUT%"=="" set "OUT=output\designed.wav"
if not exist output mkdir output
"%~dp0bin\audiocpp_cli.exe" --task tts --family omnivoice --model "%~dp0models\OmniVoice-GGUF" --backend vulkan --text "%~1" --instruct "%~2" --out "%OUT%" --metrics
exit /b 0
:usage
echo Usage: design.bat "Text to speak" "instruct attributes" [output.wav]
exit /b 1
