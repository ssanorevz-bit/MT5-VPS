# =============================================================
# setup_vps.ps1 — Lightnode VPS Auto Setup
# =============================================================
# รันครั้งเดียวหลังสร้าง VPS ใหม่ → ทุกอย่างพร้อมใน ~3 นาที
#
# วิธีใช้ (PowerShell Administrator):
#   irm https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/setup_vps.ps1 | iex
# =============================================================

$ErrorActionPreference = "Stop"

# ── Config ────────────────────────────────────────────────────
# แก้ URL นี้ให้ตรงกับ GitHub repo ของคุณ
$SCRIPT_URL  = "https://raw.githubusercontent.com/ssanorevz-bit/MT5-VPS/main/collect_mt5_tick_dom.py"
$MT5_URL     = "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
$QUANT_DIR   = "C:\quant"
$STARTUP_DIR = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  VPS Setup — Quant Collector"              -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# ── Step 1: สร้าง folder ──────────────────────────────────────
Write-Host "`n[1/5] สร้าง folder C:\quant ..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $QUANT_DIR | Out-Null
Write-Host "      OK" -ForegroundColor Green

# ── Step 2: ติดตั้ง Python ───────────────────────────────────
Write-Host "`n[2/5] ติดตั้ง Python 3.11 ..." -ForegroundColor Yellow
$pythonCheck = Get-Command python -ErrorAction SilentlyContinue
if ($pythonCheck) {
    Write-Host "      Python มีอยู่แล้ว: $($pythonCheck.Source)" -ForegroundColor Green
} else {
    $pythonInstaller = "$env:TEMP\python311.exe"
    Write-Host "      กำลังดาวน์โหลด Python 3.11 ..." -ForegroundColor Gray
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" -OutFile $pythonInstaller -UseBasicParsing
    Write-Host "      กำลังติดตั้ง ..." -ForegroundColor Gray
    Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
    Remove-Item $pythonInstaller -Force
    # refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Host "      Python ติดตั้งสำเร็จ" -ForegroundColor Green
}

# ── Step 3: ติดตั้ง Python packages ─────────────────────────
Write-Host "`n[3/5] ติดตั้ง Python packages ..." -ForegroundColor Yellow
python -m pip install --upgrade pip --quiet
python -m pip install MetaTrader5 pandas pyarrow --quiet
Write-Host "      MetaTrader5, pandas, pyarrow — OK" -ForegroundColor Green

# ── Step 4: ดาวน์โหลด collector script ──────────────────────
Write-Host "`n[4/5] ดาวน์โหลด collect_mt5_tick_dom.py ..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $SCRIPT_URL -OutFile "$QUANT_DIR\collect_mt5_tick_dom.py" -UseBasicParsing
Write-Host "      ดาวน์โหลดสำเร็จ → $QUANT_DIR\collect_mt5_tick_dom.py" -ForegroundColor Green

# ── Step 5: สร้าง run_collector.bat + ใส่ Startup ────────────
Write-Host "`n[5/5] สร้าง run_collector.bat + ตั้ง Startup ..." -ForegroundColor Yellow

$batContent = @"
@echo off
timeout /t 10 /nobreak
cd /d C:\quant
python collect_mt5_tick_dom.py
"@

$batContent | Out-File -FilePath "$QUANT_DIR\run_collector.bat" -Encoding ascii
Copy-Item "$QUANT_DIR\run_collector.bat" "$STARTUP_DIR\run_collector.bat" -Force
Write-Host "      .bat สร้างแล้ว + ใส่ Startup folder แล้ว" -ForegroundColor Green

# ── ดาวน์โหลด MT5 Installer ──────────────────────────────────
Write-Host "`n[+] ดาวน์โหลด MT5 installer ..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $MT5_URL -OutFile "$QUANT_DIR\mt5setup.exe" -UseBasicParsing
Write-Host "    MT5 installer → $QUANT_DIR\mt5setup.exe" -ForegroundColor Green
Write-Host "    (เปิดติดตั้งด้วยตัวเองหลัง script นี้จบ)" -ForegroundColor Gray

# ── สรุป ──────────────────────────────────────────────────────
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  Setup เสร็จแล้ว!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ขั้นตอนต่อไป:" -ForegroundColor White
Write-Host "  1. ติดตั้ง MT5: $QUANT_DIR\mt5setup.exe" -ForegroundColor White
Write-Host "  2. Login MT5 + ใส่ OTP" -ForegroundColor White
Write-Host "  3. Script จะ start อัตโนมัติ (รอใน background แล้ว)" -ForegroundColor White
Write-Host ""
