@echo off
rem Usage: clone.bat "Text to speak" ref.wav [output.wav] ["transcript of ref.wav"]
setlocal
if "%~1"=="" goto :usage
if "%~2"=="" goto :usage
set "OUT=%~3"
if "%OUT%"=="" set "OUT=output\cloned.wav"
set "REFTEXT=%~4"
set "REFTEXTARG="
if not "%REFTEXT%"=="" set "REFTEXTARG=--reference-text %REFTEXT%"
if not exist output mkdir output
"%~dp0bin\audiocpp_cli.exe" --task tts --family omnivoice --model "%~dp0models\OmniVoice-GGUF" --backend vulkan --text "%~1" --voice-ref "%~2" %REFTEXTARG% --out "%OUT%" --metrics
exit /b 0
:usage
echo Usage: clone.bat "Text to speak" ref.wav [output.wav] ["transcript of ref.wav"]
exit /b 1
