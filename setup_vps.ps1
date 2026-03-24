# =============================================================
# setup_vps.ps1 — Lightnode VPS Auto Setup (ไม่รวม MT5)
# =============================================================
# วิธีใช้ (PowerShell Administrator):
#   irm https://raw.githubusercontent.com/ssanorevz-bit/MT5-VPS/main/setup_vps.ps1 | iex
# =============================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  VPS Setup — Quant Collector"              -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# [1] สร้าง folder
New-Item -ItemType Directory -Force -Path C:\quant | Out-Null
Write-Host "[1/4] folder C:\quant OK" -ForegroundColor Green

# [2] ติดตั้ง Python 3.11
Write-Host "[2/4] ดาวน์โหลด + ติดตั้ง Python 3.11 ..." -ForegroundColor Yellow
Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" -OutFile "$env:TEMP\py.exe" -UseBasicParsing
Start-Process "$env:TEMP\py.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
Write-Host "[2/4] Python OK" -ForegroundColor Green

# [3] pip packages + download script
Write-Host "[3/4] ติดตั้ง packages + ดาวน์โหลด script ..." -ForegroundColor Yellow
python -m pip install MetaTrader5 pandas pyarrow -q
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ssanorevz-bit/MT5-VPS/main/collect_mt5_tick_dom.py" -OutFile "C:\quant\collect_mt5_tick_dom.py" -UseBasicParsing
Write-Host "[3/4] packages + script OK" -ForegroundColor Green

# [4] สร้าง .bat + ใส่ Startup
Write-Host "[4/4] ตั้ง Startup ..." -ForegroundColor Yellow
"@echo off`ntimeout /t 10 /nobreak`ncd /d C:\quant`npython collect_mt5_tick_dom.py" | Out-File "C:\quant\run_collector.bat" -Encoding ascii
Copy-Item "C:\quant\run_collector.bat" "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\run_collector.bat" -Force
Write-Host "[4/4] Startup OK" -ForegroundColor Green

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Setup เสร็จ! ติดตั้ง MT5 แล้ว Login ได้เลย" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
