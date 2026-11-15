# Reproducible installer for OmniVoice-on-Vulkan (Windows).
# Downloads the pinned, checksummed artifacts from versions.json and installs them.
#
# Usage (from the repository root):
#   powershell -ExecutionPolicy Bypass -File setup.ps1                 # full install
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -SkipModel      # runtime only
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -SmokeTest      # install + generate a sample
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -Force          # re-download even if cached
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -ModelPrecision f16
#
# Windows PowerShell 5.1+. Linux: use setup.sh or the Nix flake instead.
# Needs ~4 GB free disk.

#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SkipModel,
    [switch]$SmokeTest,
    [switch]$Force,
    [ValidateSet('q8_0', 'bf16', 'f16')]
    [string]$ModelPrecision = 'q8_0'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$versions = Get-Content -Path (Join-Path $root 'versions.json') -Raw | ConvertFrom-Json
$cacheDir = Join-Path $root '.cache\downloads'
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

function Get-Sha256([string]$Path) {
    (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Download $spec (url/sha256/filename) into the cache unless a valid copy is already there.
# Returns the cached file path.
function Get-CachedArtifact($spec, [string]$label) {
    $dest = Join-Path $cacheDir $spec.filename
    if (-not $Force -and (Test-Path $dest)) {
        if ((Get-Sha256 $dest) -eq $spec.sha256) {
            Write-Host "[ok] $label already cached (checksum matches)"
            return $dest
        }
        Write-Host "[..] $label cached copy failed checksum, re-downloading"
    } else {
        Write-Host "[..] downloading $label"
    }
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & $curl.Source -sSL --fail -o $dest $spec.url
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $($spec.url)" }
    } else {
        Invoke-WebRequest -Uri $spec.url -OutFile $dest -UseBasicParsing
    }
    $actual = Get-Sha256 $dest
    if ($actual -ne $spec.sha256) {
        throw ("Checksum mismatch for {0}:`n  expected: {1}`n  actual:   {2}`nThe upstream artifact may have changed; update versions.json if intentional." -f $label, $spec.sha256, $actual)
    }
    Write-Host "[ok] $label downloaded (checksum matches)"
    $dest
}

Write-Host "=== OmniVoice on Vulkan - setup ==="
Write-Host ("audio.cpp {0} | model precision {1}" -f $versions.audio_cpp.version, $ModelPrecision)

# --- 1. Runtime (audio.cpp portable Vulkan build) ---
$asset = $versions.audio_cpp.assets.'windows-x64'
$runtime = Get-CachedArtifact $asset 'audio.cpp runtime'
$stampPath = Join-Path $root 'bin\.setup-stamp.json'
$stampOk = $false
if (-not $Force -and (Test-Path $stampPath)) {
    try {
        $stamp = Get-Content -Path $stampPath -Raw | ConvertFrom-Json
        $stampOk = ($stamp.runtime_sha256 -eq $asset.sha256)
    } catch { $stampOk = $false }
}
if ($stampOk) {
    Write-Host "[ok] runtime already installed (bin\.setup-stamp.json matches)"
} else {
    Write-Host "[..] extracting runtime -> bin\"
    $tmp = Join-Path $cacheDir 'extract-runtime'
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Expand-Archive -Path $runtime -DestinationPath $tmp -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'bin') | Out-Null
    Copy-Item -Path (Join-Path $tmp '*') -Destination (Join-Path $root 'bin') -Recurse -Force
    Remove-Item -Recurse -Force $tmp
    @{
        runtime_sha256 = $asset.sha256
        installed_at   = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json | Set-Content -Path $stampPath -Encoding UTF8
    Write-Host "[ok] runtime installed"
}

# --- 2. Model (OmniVoice GGUF) ---
if (-not $SkipModel) {
    $modelSpec = $versions.omnivoice_gguf.precision.$ModelPrecision
    $modelDir = Join-Path (Join-Path $root 'models') $versions.omnivoice_gguf.dir
    New-Item -ItemType Directory -Force -Path $modelDir | Out-Null
    $modelDest = Join-Path $modelDir $modelSpec.filename
    $modelOk = $false
    if (-not $Force -and (Test-Path $modelDest)) {
        if ((Get-Sha256 $modelDest) -eq $modelSpec.sha256) {
            Write-Host "[ok] model already installed (checksum matches)"
            $modelOk = $true
        } else {
            Write-Host "[..] installed model failed checksum, re-downloading"
        }
    }
    if (-not $modelOk) {
        $modelCache = Get-CachedArtifact $modelSpec "OmniVoice $ModelPrecision model"
        Move-Item -Path $modelCache -Destination $modelDest -Force
        if ((Get-Sha256 $modelDest) -ne $modelSpec.sha256) { throw 'Model install failed final checksum' }
        Write-Host "[ok] model installed -> $modelDest"
    }
}

# --- 3. Smoke test ---
if ($SmokeTest) {
    Write-Host '[..] smoke test: device listing'
    & (Join-Path $root 'bin\audiocpp_cli.exe') --list-devices
    if ($LASTEXITCODE -ne 0) { throw 'Device listing failed' }
    if (-not $SkipModel) {
        Write-Host '[..] smoke test: generating sample (this loads the model, ~30 s first run)'
        $smokeWav = Join-Path $cacheDir 'smoke.wav'
        & (Join-Path $root 'bin\audiocpp_cli.exe') --task tts --family omnivoice `
            --model $modelDest --backend vulkan `
            --text 'OmniVoice setup smoke test passed.' --out $smokeWav --metrics
        if ($LASTEXITCODE -ne 0) { throw 'Smoke test generation failed' }
        Write-Host "[ok] smoke sample written to $smokeWav"
    }
}

Write-Host '=== done ==='
if (-not $SkipModel) {
    Write-Host 'Try:  tts.bat "Hello world."    or    server.bat  (WebUI at http://127.0.0.1:8080)'
}
