# Free Reel Effects — installer for Windows (PowerShell)
# Created by GALTech School of Technology · www.galtechlearning.com
# Run:  powershell -ExecutionPolicy Bypass -File install.ps1
Set-Location $PSScriptRoot
Write-Host "`nFree Reel Effects — installer" -ForegroundColor White
Write-Host "Created by GALTech School of Technology · www.galtechlearning.com`n"

function Have($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }

Write-Host "1. System tools"
if (-not (Have python)) {
  Write-Host "  -> Python missing, installing with winget..." -ForegroundColor Yellow
  winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements; Refresh-Path
}
if (Have python) { Write-Host "  OK $(python --version)" -ForegroundColor Green } else { Write-Host "  X Install Python 3.9+ from python.org, then run again" -ForegroundColor Red; exit 1 }
if (-not (Have ffmpeg)) {
  Write-Host "  -> ffmpeg missing, installing with winget..." -ForegroundColor Yellow
  winget install -e --id Gyan.FFmpeg --accept-source-agreements --accept-package-agreements; Refresh-Path
}
if (Have ffmpeg) { Write-Host "  OK ffmpeg found" -ForegroundColor Green } else { Write-Host "  X ffmpeg not found - open a new PowerShell window and run again" -ForegroundColor Red; exit 1 }
if (-not (Have curl.exe)) { Write-Host "  X curl.exe missing (included in Windows 10+)" -ForegroundColor Red; exit 1 }

Write-Host "`n2. Python packages"
python -m pip install -q numpy opencv-python-headless pillow onnxruntime
python -c "import numpy, cv2, PIL, onnxruntime; print('  OK packages ready')"
if ($LASTEXITCODE -ne 0) { Write-Host "  X Python packages failed to install" -ForegroundColor Red; exit 1 }

Write-Host "`n3. Free AI model + fonts (~180 MB, once)"
python free-reel-effects\fx.py setup
if ($LASTEXITCODE -ne 0) { Write-Host "  X Download failed - check your internet" -ForegroundColor Red; exit 1 }

Write-Host "`nAll set! Try it:" -ForegroundColor Green
Write-Host '  python free-reel-effects\fx.py all --input my_clip.mp4 --output my_reel.mp4 --title "My Shop" --word SALE'
Write-Host "`nFree Reel Effects · created by GALTech School of Technology · www.galtechlearning.com"
